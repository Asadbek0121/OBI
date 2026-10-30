import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/localization/app_translations.dart';

class GlobalSearchModal extends StatefulWidget {
  const GlobalSearchModal({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Search',
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const GlobalSearchModal();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: anim1,
              curve: Curves.easeOutBack,
            ),
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
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
            width: 800, // Widened for PC
            constraints: const BoxConstraints(maxHeight: 650),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                 ? const Color(0xFF1E1E1E).withValues(alpha: 0.6)
                 : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : Colors.black.withValues(alpha: 0.12),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15), 
                  blurRadius: 50, 
                  spreadRadius: 0, 
                  offset: const Offset(0, 25)
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modern Header / Input
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white.withValues(alpha: 0.05) 
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 28, color: Colors.grey),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              onChanged: _onSearch,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ).copyWith(
                                  hintText: AppTranslations().text('search_input_hint'),
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 18),
                                ),
                              ),
                          ),
                          if (_isLoading)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                            ),
                            child: const Text("ESC", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.transparent),
                  
                  // Results
                  if (_results.isEmpty && _controller.text.isNotEmpty && !_isLoading)
                     Padding(
                       padding: const EdgeInsets.all(48.0),
                       child: Column(
                         children: [
                           Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                           const SizedBox(height: 16),
                           Text("Hech narsa topilmadi", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                         ],
                       ),
                     )
                  else if (_results.isNotEmpty)
                    Flexible(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        itemCount: _results.length,
                        separatorBuilder: (c, i) => Divider(height: 1, indent: 72, color: Colors.grey.withValues(alpha: 0.1)),
                        itemBuilder: (context, index) {
                           final item = _results[index];
                           return _SearchResultItem(item: item);
                        },
                      ),
                    )
                  else
                     // Initial State Shortcuts
                     Padding(
                       padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text("YORDAM", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey.shade500, letterSpacing: 1.2)),
                           const SizedBox(height: 12),
                           const Row(
                             children: [
                               Expanded(child: _ShortcutHelpRow(icon: Icons.inventory_2_rounded, text: "Mahsulot nomi")),
                               Expanded(child: _ShortcutHelpRow(icon: Icons.chair_rounded, text: "Jihoz nomi")),
                             ],
                           ),
                           const Row(
                             children: [
                               Expanded(child: _ShortcutHelpRow(icon: Icons.person_rounded, text: "Xodim ismi")),
                               Expanded(child: _ShortcutHelpRow(icon: Icons.history_rounded, text: "Tarix (YYYY-MM-DD)")),
                             ],
                           ),
                         ],
                       ),
                     ),
                ],
              ),
            ),
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
          color: color.withValues(alpha: 0.1),
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
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
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
