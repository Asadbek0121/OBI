import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../main.dart'; // To access scaffoldMessengerKey

class UpdateService {
  static const String _githubUser = 'Asadbek0121';
  static const String _githubRepo = 'OBI';
  static bool _isUpdatePrompted = false; // To prevent multiple banners

  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdate = false}) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubUser/$_githubRepo/releases/latest'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String latestTag = (data['tag_name'] as String);
        final String latestVersion = latestTag.replaceFirst('v', '').split('+')[0];
        
        if (_isNewer(latestVersion, currentVersion)) {
          if (_isUpdatePrompted && !showNoUpdate) return;
          
          String downloadUrl = "";
          String fileName = "";
          final assets = data['assets'] as List;
          
          if (assets.isNotEmpty) {
            String suffix = Platform.isWindows ? '.msix' : '.dmg';
            
            try {
              final asset = assets.firstWhere(
                (a) => a['name'].toString().toLowerCase().endsWith(suffix),
                orElse: () => assets.firstWhere((a) => a['name'].toString().toLowerCase().endsWith('.zip'))
              );
              downloadUrl = asset['browser_download_url'];
              fileName = asset['name'];
            } catch (_) {
              downloadUrl = assets[0]['browser_download_url'];
              fileName = assets[0]['name'];
            }

            if (downloadUrl.isNotEmpty) {
              _isUpdatePrompted = true;
              _showUpdateBanner(latestVersion, downloadUrl, fileName, data['body'] ?? 'Yangi imkoniyatlar va xatoliklar tuzatilgan.');
            }
          }
        } else if (showNoUpdate) {
           scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text("Siz eng oxirgi talqindan foydalanmoqdasiz.")),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ [Updater] Xatolik: $e");
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('+')[0];
      final c = current.split('+')[0];
      List<int> latestParts = l.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = c.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < latestParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateBanner(String version, String url, String fileName, String notes) {
    scaffoldMessengerKey.currentState?.showMaterialBanner(
      MaterialBanner(
        elevation: 10,
        backgroundColor: Colors.blueAccent.shade700,
        leadingPadding: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('YANGI TALQIN TAYYOR (v$version)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('Tizimni yangilash tavsiya etiladi.', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
          child: const Icon(Icons.rocket_launch, color: Colors.white, size: 28),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blueAccent.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              scaffoldMessengerKey.currentState?.hideCurrentMaterialBanner();
              _showDownloadProgress(url, fileName, notes, version);
            },
            child: const Text('YANGILASH', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              scaffoldMessengerKey.currentState?.hideCurrentMaterialBanner();
              // Prevent it from popping back up instantly
              Future.delayed(const Duration(hours: 1), () => _isUpdatePrompted = false);
            },
            child: const Text('KEYINROQ', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  static void _showDownloadProgress(String url, String fileName, String notes, String version) {
    // We need a context for full-screen dialog, so we use the navigatorKey or just a local check.
    // Since we don't have a global navigator key easily in main (we can add it), but for now:
    showGeneralDialog(
      context: scaffoldMessengerKey.currentContext!,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => _BeautifulProgressView(
        url: url, fileName: fileName, notes: notes, version: version
      ),
    );
  }
}

class _BeautifulProgressView extends StatefulWidget {
  final String url;
  final String fileName;
  final String notes;
  final String version;
  const _BeautifulProgressView({required this.url, required this.fileName, required this.notes, required this.version});

  @override
  State<_BeautifulProgressView> createState() => _BeautifulProgressViewState();
}

class _BeautifulProgressViewState extends State<_BeautifulProgressView> with SingleTickerProviderStateMixin {
  double _progress = 0;
  String _status = "Yuklash boshlanmoqda...";
  bool _isError = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _startDownload();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, widget.fileName);

      await dio.download(widget.url, savePath, onReceiveProgress: (count, total) {
        if (total != -1) {
          setState(() {
            _progress = count / total;
            _status = "Tizim yuklanmoqda: ${(_progress * 100).toStringAsFixed(0)}%";
          });
        }
      });

      setState(() { _status = "Barchasi tayyor! O'rnatilmoqda..."; _progress = 1.0; });
      await Future.delayed(const Duration(milliseconds: 800));

      if (Platform.isWindows) {
        try {
           await Process.run('powershell', ['-Command', 'Add-AppxPackage', '-Path', '"$savePath"', '-ForceUpdateFromAnyVersion'], runInShell: true);
        } catch (_) {}
        await Process.run('start', [savePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [savePath]);
      }
      exit(0);
    } catch (e) {
      setState(() { _isError = true; _status = "Xatolik: $e"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 40, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Stack(
                alignment: Alignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.15).animate(_pulseController),
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(color: Colors.blueAccent.withAlpha(20), shape: BoxShape.circle),
                    ),
                  ),
                  const Icon(Icons.cloud_download_rounded, color: Colors.blueAccent, size: 50),
                ],
              ),
              const SizedBox(height: 24),
              Text("Yangilanish (v${widget.version})", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              
              const SizedBox(height: 32),
              
              // Custom Progress Bar
              Container(
                height: 12,
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.cyanAccent]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.blueAccent.withAlpha(100), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
              
              // Release Notes
              if (widget.notes.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("YANGILIKLAR:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Text(widget.notes, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87)),
                  ),
                ),
              ],
              
              if (_isError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("YOPISH"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
