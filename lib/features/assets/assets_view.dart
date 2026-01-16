import 'package:flutter/material.dart';
import 'package:clinical_warehouse/core/database/database_helper.dart';
import 'package:clinical_warehouse/core/theme/app_colors.dart';
import 'package:clinical_warehouse/core/widgets/glass_container.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'dart:math';

class AssetsView extends StatefulWidget {
  const AssetsView({super.key});

  @override
  State<AssetsView> createState() => _AssetsViewState();
}

class _AssetsViewState extends State<AssetsView> {
  List<Map<String, dynamic>> _allAssets = []; // Store full list
  List<Map<String, dynamic>> _filteredAssets = []; // Store filtered list
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    await DatabaseHelper.instance.createAssetsTableIfNeeded();
    final data = await DatabaseHelper.instance.getAllAssets();
    if (mounted) {
      setState(() {
        _allAssets = data;
        _filterAssets(_searchCtrl.text); // Apply current filter
        _isLoading = false;
      });
    }
  }

  void _filterAssets(String query) {
    if (query.isEmpty) {
      setState(() => _filteredAssets = _allAssets);
      return;
    }

    final lower = query.toLowerCase();
    final filtered = _allAssets.where((asset) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final model = (asset['model'] ?? '').toString().toLowerCase();
      final loc = (asset['location'] ?? '').toString().toLowerCase();
      final code = (asset['barcode'] ?? '').toString().toLowerCase();
      
      return name.contains(lower) || 
             model.contains(lower) || 
             loc.contains(lower) || 
             code.contains(lower);
    }).toList();

    setState(() => _filteredAssets = filtered);
  }

  void _showAddAssetModal() {
    showDialog(
      context: context,
      builder: (context) => const _AddAssetDialog(),
    ).then((val) {
      if (val == true) _loadAssets();
    });
  }

  void _showBarcodePreview(Map<String, dynamic> asset) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Shtrix Kod: ${asset['name']}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: asset['barcode'],
                  width: 300,
                  height: 100,
                  drawText: true,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text("Yopish"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Fake Print
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("Printerga yuborildi... (Simulyatsiya)"))
                      );
                    },
                    icon: const Icon(Icons.print),
                    label: const Text("Chop etish"),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _deleteAsset(int id, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          width: 400,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 64, color: AppColors.error),
              const SizedBox(height: 24),
              const Text("O'chirishni tasdiqlaysizmi?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text("\"$name\" bazadan butunlay o'chiriladi. Bu amalni qaytarib bo'lmaydi.", 
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Bekor qilish", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await DatabaseHelper.instance.deleteAsset(id);
                        if (mounted) {
                          Navigator.pop(context);
                          _loadAssets();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("O'chirish", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header & Search
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
             Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 const Text("Asosiy Vositalar", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1)),
                 const SizedBox(height: 4),
                 Text("Binodagi texnika va jihozlar boshqaruvi", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
               ],
             ),
             Row(
               children: [
                 // Refined Search Bar
                 AnimatedContainer(
                   duration: const Duration(milliseconds: 300),
                   width: 350,
                   child: GlassContainer(
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                     borderRadius: 16,
                     child: TextField(
                       controller: _searchCtrl,
                       onChanged: _filterAssets,
                       style: const TextStyle(fontSize: 14),
                       decoration: InputDecoration(
                         hintText: "Nom, Xona yoki Shtrix-kod...",
                         hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                         border: InputBorder.none,
                         focusedBorder: InputBorder.none,
                         enabledBorder: InputBorder.none,
                         icon: Icon(Icons.search_rounded, color: AppColors.primary.withOpacity(0.7), size: 22),
                       ),
                     ),
                   ),
                 ),
                 const SizedBox(width: 16),
                 ElevatedButton.icon(
                   onPressed: _showAddAssetModal,
                   icon: const Icon(Icons.add_rounded, size: 20),
                   label: const Text("Yangi Jihoz", style: TextStyle(fontWeight: FontWeight.bold)),
                   style: ElevatedButton.styleFrom(
                     backgroundColor: AppColors.primary,
                     foregroundColor: Colors.white,
                     elevation: 8,
                     shadowColor: AppColors.primary.withOpacity(0.4),
                     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   ),
                 ),
               ],
             ),
          ],
        ),
        const SizedBox(height: 32),
        
        // Grid
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _filteredAssets.isEmpty 
               ? Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Container(
                         padding: const EdgeInsets.all(32),
                         decoration: BoxDecoration(
                           color: Colors.grey[100],
                           shape: BoxShape.circle,
                         ),
                         child: Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[300]),
                       ),
                       const SizedBox(height: 24),
                       Text(
                         _allAssets.isEmpty ? "Hozircha jihozlar yo'q" : "Hech narsa topilmadi", 
                         style: TextStyle(color: Colors.grey[700], fontSize: 18, fontWeight: FontWeight.w500)
                       ),
                       const SizedBox(height: 8),
                       Text(
                         _allAssets.isEmpty ? "Yangi jihoz qo'shish uchun yuqoridagi tugmani bosing" : "Boshqa so'z bilan qidirib ko'ring",
                         style: TextStyle(color: Colors.grey[500], fontSize: 14),
                       ),
                     ],
                   ),
                 )
               : GridView.builder(
                   padding: const EdgeInsets.only(bottom: 100),
                   gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                     maxCrossAxisExtent: 320,
                     childAspectRatio: 1.15,
                     crossAxisSpacing: 20,
                     mainAxisSpacing: 20,
                   ),
                   itemCount: _filteredAssets.length,
                   itemBuilder: (context, index) {
                     final asset = _filteredAssets[index];
                     return _AssetCard(
                       asset: asset, 
                       onPrint: () => _showBarcodePreview(asset),
                       onDelete: () => _deleteAsset(asset['id'], asset['name']),
                     );
                   },
                 ),
        ),
      ],
    );
  }
}

class _AssetCard extends StatelessWidget {
  final Map<String, dynamic> asset;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  const _AssetCard({
    required this.asset, 
    required this.onPrint,
    required this.onDelete,
  });

  IconData _getIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('komp') || n.contains('laptop') || n.contains('noutbuk')) return Icons.laptop_mac_rounded;
    if (n.contains('stol')) return Icons.table_restaurant_rounded;
    if (n.contains('stul')) return Icons.chair_rounded;
    if (n.contains('printer')) return Icons.print_rounded;
    if (n.contains('monitor')) return Icons.desktop_windows_rounded;
    if (n.contains('telefon')) return Icons.phone_android_rounded;
    return Icons.inventory_2_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 24,
      child: Stack(
        children: [
          InkWell(
            onTap: onPrint,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_getIcon(asset['name']), color: AppColors.primary, size: 24),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_2_rounded, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              asset['barcode'].toString().split('-').last, 
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600])
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    asset['name'], 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5), 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis
                  ),
                  const SizedBox(height: 4),
                  Text(
                    asset['model'] ?? '-', 
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  const Divider(height: 24, color: AppColors.glassBorder),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 14, color: Colors.blue.withOpacity(0.7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          asset['location'], 
                          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashRadius: 20,
                tooltip: "O'chirish",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAssetDialog extends StatefulWidget {
  const _AddAssetDialog();

  @override
  State<_AddAssetDialog> createState() => _AddAssetDialogState();
}

class _AddAssetDialogState extends State<_AddAssetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      // Generate Barcode
      final idSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
      final random = Random().nextInt(99).toString().padLeft(2, '0');
      final barcode = "AST-$idSuffix$random";

      final asset = {
        'name': _nameCtrl.text,
        'model': _modelCtrl.text,
        'color': _colorCtrl.text,
        'location': _locationCtrl.text,
        'barcode': barcode,
        'created_at': DateTime.now().toIso8601String(),
      };

      await DatabaseHelper.instance.insertAsset(asset);
      if (mounted) Navigator.pop(context, true);
    }
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary.withOpacity(0.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassContainer(
        width: 550,
        padding: const EdgeInsets.all(40),
        borderRadius: 32,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.add_business_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 20),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Yangi Jihoz", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                      Text("Ma'lumotlarni to'ldiring", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco("Buyum Nomi (masalan: Stol, Printer)", Icons.title_rounded),
                validator: (v) => v!.isEmpty ? "Nomini yozing" : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _modelCtrl,
                      decoration: _inputDeco("Model/Marka", Icons.model_training_rounded),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _colorCtrl,
                      decoration: _inputDeco("Rangi", Icons.palette_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _locationCtrl,
                decoration: _inputDeco("Joylashuv (xona nomi)", Icons.room_rounded),
                validator: (v) => v!.isEmpty ? "Joyini ko'rsating" : null,
              ),
              
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Bekor qilish", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    child: const Text("Saqlash va Kod yaratish", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
