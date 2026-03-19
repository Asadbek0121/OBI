import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class UpdateService {
  static const String _githubUser = 'Asadbek0121';
  static const String _githubRepo = 'OBI';

  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdate = false}) async {
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
          String fileName = "";
          final assets = data['assets'] as List;
          
          if (assets.isNotEmpty) {
            if (Platform.isWindows) {
              final msix = assets.firstWhere(
                (a) => a['name'].toString().toLowerCase().endsWith('.msix'), 
                orElse: () => assets[0]
              );
              downloadUrl = msix['browser_download_url'];
              fileName = msix['name'];
            } else if (Platform.isMacOS) {
              final dmg = assets.firstWhere(
                (a) => a['name'].toString().toLowerCase().endsWith('.dmg'),
                orElse: () => assets[0]
              );
              downloadUrl = dmg['browser_download_url'];
              fileName = dmg['name'];
            }
            
            if (downloadUrl.isNotEmpty && context.mounted) {
              _showUpdateBanner(context, latestVersion, downloadUrl, fileName, data['body'] ?? '');
            }
          }
        } else if (showNoUpdate && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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

  static void _showUpdateBanner(BuildContext context, String version, String url, String fileName, String notes) {
     ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.blueAccent.withAlpha(50),
        content: Text('Yangi talqin tayyor: v$version', style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.system_update, color: Colors.blueAccent),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _showDownloadProgress(context, url, fileName, notes);
            },
            child: const Text('YANGILASH', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('YOPISH', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  static void _showDownloadProgress(BuildContext context, String url, String fileName, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(url: url, fileName: fileName, notes: notes),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String fileName;
  final String notes;
  const _DownloadProgressDialog({required this.url, required this.fileName, required this.notes});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = "Yuklanmoqda...";
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, widget.fileName);

      await dio.download(
        widget.url,
        savePath,
        onReceiveProgress: (count, total) {
          if (total != -1) {
            setState(() {
              _progress = count / total;
            });
          }
        },
      );

      setState(() {
        _progress = 1.0;
        _status = "O'rnatilmoqda...";
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (Platform.isWindows) {
        try {
           // PowerShell attempt for background install
           await Process.run('powershell', [
             '-Command', 
             'Add-AppxPackage', '-Path', '"$savePath"', '-ForceUpdateFromAnyVersion'
           ], runInShell: true);
        } catch (_) {}
        // Fallback or secondary trigger: Launch UI if PowerShell was silent but app didn't exit yet
        await Process.run('start', [savePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [savePath]);
      }

      exit(0); 
    } catch (e) {
      setState(() {
        _isError = true;
        _status = "Xatolik: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Tizimni yangilash"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.notes.isNotEmpty) ...[
            const Text("Yangiliklar:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(child: Text(widget.notes, style: const TextStyle(fontSize: 12))),
            ),
            const SizedBox(height: 15),
          ],
          Text(_status, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 15),
          if (!_isError)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.withAlpha(50),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              minHeight: 10,
            ),
          const SizedBox(height: 10),
          if (!_isError)
            Text("${(_progress * 100).toStringAsFixed(0)}%", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          if (_isError)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Yopish"),
            ),
        ],
      ),
    );
  }
}
