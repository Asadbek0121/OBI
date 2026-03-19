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
                (a) => a['name'].toString().endsWith('.msix') || a['name'].toString().endsWith('.exe'), 
                orElse: () => assets[0]
              );
              downloadUrl = msix['browser_download_url'];
              fileName = msix['name'];
            } else if (Platform.isMacOS) {
              final dmg = assets.firstWhere(
                (a) => a['name'].toString().endsWith('.dmg') || a['name'].toString().endsWith('.zip'), 
                orElse: () => assets[0]
              );
              downloadUrl = dmg['browser_download_url'];
              fileName = dmg['name'];
            }

            if (downloadUrl.isNotEmpty && context.mounted) {
              _showUpdateDialog(context, latestVersion, downloadUrl, fileName, data['body'] ?? '');
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

  static void _showUpdateDialog(BuildContext context, String version, String url, String fileName, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Text('Yangi talqin tayyor! (v$version)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tizimda yangi imkoniyatlar va xatoliklar tuzatilgan.'),
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
            onPressed: () {
              Navigator.pop(context);
              _showDownloadProgress(context, url, fileName);
            },
            child: const Text('Hozir yangilash', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void _showDownloadProgress(BuildContext context, String url, String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(url: url, fileName: fileName),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String fileName;
  const _DownloadProgressDialog({required this.url, required this.fileName});

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
        _status = "Yuklash yakunlandi. O'rnatilmoqda...";
      });

      await Future.delayed(const Duration(seconds: 1));

      // Launch installer
      if (Platform.isWindows) {
        await Process.run('start', [savePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [savePath]);
      }

      exit(0); // Close app to allow update
    } catch (e) {
      setState(() {
        _isError = true;
        _status = "Xatolik yuz berdi: $e";
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
        children: [
          Text(_status, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 20),
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
