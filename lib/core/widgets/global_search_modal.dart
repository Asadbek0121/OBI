import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:clinical_warehouse/core/database/database_helper.dart';

class GlobalSearchModal extends StatefulWidget {
  const GlobalSearchModal({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Search',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return const GlobalSearchModal();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  @override
  State<GlobalSearchModal> createState() => _GlobalSearchModalState();
}

class _GlobalSearchModalState extends State<GlobalSearchModal> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Auto focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await DatabaseHelper.instance.searchGlobal(query);
      if (mounted) {
        setState(() {
          _results = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 600),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                 ? const Color(0xFF1E1E1E) 
                 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 40, spreadRadius: 0, offset: Offset(0, 20))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header / Input
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 28, color: Colors.grey),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _onSearch,
                          style: const TextStyle(fontSize: 20),
                          decoration: InputDecoration.collapsed(
                            hintText: "Qidiruv... (Mahsulot, Xodim, Tarix)",
                            hintStyle: TextStyle(color: Colors.grey.shade400)
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text("ESC", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                // Results
                if (_results.isEmpty && _controller.text.isNotEmpty && !_isLoading)
                   Padding(
                     padding: const EdgeInsets.all(32.0),
                     child: Text("Hech narsa topilmadi", style: TextStyle(color: Colors.grey.shade500)),
                   )
                else if (_results.isNotEmpty)
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (c, i) => const Divider(height: 1, indent: 60),
                      itemBuilder: (context, index) {
                         final item = _results[index];
                         return _SearchResultItem(item: item);
                      },
                    ),
                  )
                else
                   // Initial State Shortcuts
                   Padding(
                     padding: const EdgeInsets.all(16.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text("YORDAM", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                         const SizedBox(height: 8),
                         _ShortcutHelpRow(icon: Icons.inventory_2, text: "Mahsulot nomini yozing (masalan, 'Aspirin')"),
                         _ShortcutHelpRow(icon: Icons.chair, text: "Jihoz nomini yozing (masalan, 'Stol', 'Kompyuter')"), // NEW
                         _ShortcutHelpRow(icon: Icons.person, text: "Xodim ismini yozing (masalan, 'Valijon')"),
                         _ShortcutHelpRow(icon: Icons.history, text: "Tarixni ko'rish uchun sana yoki nom yozing"),
                       ],
                     ),
                   ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutHelpRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ShortcutHelpRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _SearchResultItem({required this.item});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String title;
    String subtitle;
    String trailing;

    final type = item['type'];
    
    if (type == 'product') {
      icon = Icons.inventory_2_outlined;
      color = Colors.blue;
      title = item['name'];
      subtitle = "Omborda: ${item['stock']} ${item['unit']}";
      trailing = "MAHSULOT";
    } else if (type == 'history_in') {
      icon = Icons.download_rounded;
      color = Colors.green;
      title = item['title'];
      subtitle = "${item['subtitle']} • ${item['quantity']} kirim";
      trailing = item['date_time'].toString().substring(0, 10);
    } else if (type == 'history_out') {
      icon = Icons.upload_rounded;
      color = Colors.orange;
      title = item['title'];
      subtitle = "${item['subtitle']} • ${item['quantity']} chiqim";
      trailing = item['date_time'].toString().substring(0, 10);
    } else if (type == 'asset') { // NEW: ASSET
      icon = Icons.chair_rounded;
      color = Colors.teal;
      title = item['title'];
      subtitle = item['subtitle'] ?? ''; // Location
      trailing = "JIHOZ";
    } else { // person
      icon = Icons.person_outline;
      color = Colors.purple;
      title = item['title'];
      subtitle = item['subtitle'];
      trailing = "XODIM";
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Text(trailing, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
      ),
      onTap: () {
        // Handle navigation?
        // For MVP, just closing and maybe showing a SnackBar or filtering the main view would be ideal.
        // But the user just wants "Search". Seeing the info is often enough.
        // Let's close for now.
        Navigator.of(context).pop();
      },
    );
  }
}
