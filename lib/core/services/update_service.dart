import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../main.dart'; // To access navigatorKey and scaffoldMessengerKey

class UpdateService {
  static const String _githubUser = 'Asadbek0121';
  static const String _githubRepo = 'OBI';
  
  static bool _checking = false;
  static bool _prompted = false;
  static OverlayEntry? _overlayEntry;

  /// Main entry point to check for updates.
  /// Can be called from anywhere.
  static Future<void> checkUpdate({bool forceShowNoUpdate = false}) async {
    if (_checking || (!Platform.isWindows && !Platform.isMacOS)) return;
    _checking = true;

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubUser/$_githubRepo/releases/latest'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String latestTag = (data['tag_name'] as String);
        final String latestVersion = latestTag.replaceFirst('v', '').split('+')[0];

        if (_isNewer(latestVersion, currentVersion)) {
          if (_prompted && !forceShowNoUpdate) return;

          final assets = data['assets'] as List;
          if (assets.isNotEmpty) {
            String suffix = Platform.isWindows ? '.msix' : '.dmg';
            final asset = assets.firstWhere(
              (a) => a['name'].toString().toLowerCase().endsWith(suffix),
              orElse: () => assets[0],
            );

            _showCustomNotification(
              version: latestVersion,
              url: asset['browser_download_url'],
              fileName: asset['name'],
              notes: data['body'] ?? 'Yangi versiya tayyor!',
            );
            _prompted = true;
          }
        } else if (forceShowNoUpdate) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text("Siz eng oxirgi talqindan foydalanmoqdasiz.")),
          );
        }
      }
    } catch (e) {
      debugPrint("⚠️ [Updater] Check failed: $e");
    } finally {
      _checking = false;
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < lParts.length; i++) {
        if (i >= cParts.length) return true;
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Shows a custom, high-end overlay notification that is 
  /// context-independent and stays on top of everything.
  static void _showCustomNotification({
    required String version,
    required String url,
    required String fileName,
    required String notes,
  }) {
    if (_overlayEntry != null) return;

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _UpdateNotificationWidget(
        version: version,
        onUpdate: () {
          _removeNotification();
          _showDownloadDialog(url, fileName, notes, version);
        },
        onDismiss: () {
          _removeNotification();
          // Reset prompted after 30 mins to remind again
          Future.delayed(const Duration(minutes: 30), () => _prompted = false);
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  static void _removeNotification() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static void _showDownloadDialog(String url, String fileName, String notes, String version) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) => _DownloadView(
        url: url, fileName: fileName, notes: notes, version: version
      ),
    );
  }
}

/// --- UI COMPONENTS ---

class _UpdateNotificationWidget extends StatefulWidget {
  final String version;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  const _UpdateNotificationWidget({
    required this.version,
    required this.onUpdate,
    required this.onDismiss,
  });

  @override
  State<_UpdateNotificationWidget> createState() => _UpdateNotificationWidgetState();
}

class _UpdateNotificationWidgetState extends State<_UpdateNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _offsetAnimation = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40, left: 0, right: 0,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 500,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E), // Dark theme consistent
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 30, spreadRadius: 5)],
                border: Border.all(color: Colors.blueAccent.withAlpha(80), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blueAccent.withAlpha(30), shape: BoxShape.circle),
                    child: const Icon(Icons.system_update_alt_rounded, color: Colors.blueAccent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Yangi versiya tayyor: v${widget.version}", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Text("Ilovani yangilash tavsiya etiladi", 
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: widget.onUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("YANGILASH", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadView extends StatefulWidget {
  final String url;
  final String fileName;
  final String notes;
  final String version;
  const _DownloadView({required this.url, required this.fileName, required this.notes, required this.version});

  @override
  State<_DownloadView> createState() => _DownloadViewState();
}

class _DownloadViewState extends State<_DownloadView> {
  double _progress = 0;
  String _status = "Ulanmoqda...";
  bool _error = false;
  String _errorMessage = "";

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

      await dio.download(widget.url, savePath, onReceiveProgress: (count, total) {
        if (total != -1) {
          setState(() {
            _progress = count / total;
            _status = "Yuklanmoqda: ${(_progress * 100).toStringAsFixed(0)}%";
          });
        }
      });

      setState(() { _status = "Tayyor! O'rnatilmoqda..."; _progress = 1.0; });
      await Future.delayed(const Duration(milliseconds: 1000));

      if (Platform.isWindows) {
        // Silent install attempt
        await Process.run('powershell', ['-Command', 'Add-AppxPackage', '-Path', '"$savePath"', '-ForceUpdateFromAnyVersion'], runInShell: true);
        // Fallback or restart trigger
        await Process.run('start', [savePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [savePath]);
      }
      
      exit(0);
    } catch (e) {
      setState(() { _error = true; _errorMessage = e.toString(); _status = "Xatolik yuz berdi"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(150), blurRadius: 50)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 60),
              const SizedBox(height: 24),
              Text("Tizim Yangilanmoqda", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_status, style: TextStyle(color: _error ? Colors.redAccent : Colors.white60)),
              
              const SizedBox(height: 32),
              
              // Custom Linear Progress
              if (!_error) ...[
                Container(
                  height: 8, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.cyanAccent]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Release Notes
              if (widget.notes.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("YANGILIKLAR:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(20)),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(widget.notes, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
                  ),
                ),
              ],

              if (_error) ...[
                const SizedBox(height: 24),
                Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("YOPISH", style: TextStyle(color: Colors.white54)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
