import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/theme/app_colors.dart';
import '../../core/localization/app_translations.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/telegram_service.dart';
import '../../core/utils/app_notifications.dart';
import 'package:intl/intl.dart';
import '../../core/services/print_service.dart';

class TelegramManagementView extends StatefulWidget {
  const TelegramManagementView({super.key});

  @override
  State<TelegramManagementView> createState() => _TelegramManagementViewState();
}

class _TelegramManagementViewState extends State<TelegramManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _telegramService = TelegramService();
  final _tokenController = TextEditingController();
  
  bool _isLoadingOrders = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = await DatabaseHelper.instance.database;
    final ordersResult = await db.query('branch_orders', orderBy: 'id DESC');
    final users = await _telegramService.getUsers();
    final token = await _telegramService.getBotToken();
    
    // Attach items to orders
    List<Map<String, dynamic>> ordersWithItems = [];
    for (var order in ordersResult) {
       final items = await db.query('branch_order_items', where: 'order_id = ?', whereArgs: [order['id']]);
       final mutableOrder = Map<String, dynamic>.from(order);
       mutableOrder['items'] = items;
       ordersWithItems.add(mutableOrder);
    }
    
    if (mounted) {
      setState(() {
        _orders = ordersWithItems;
        _users = users;
        _tokenController.text = token ?? '';
        _isLoadingOrders = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Telegram Bot Boshqaruvi", style: Theme.of(context).textTheme.headlineMedium),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
          ],
        ),
        const SizedBox(height: 16),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "📦 Buyurtmalar"),
            Tab(text: "⚙️ Bot Sozlamalari"),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOrdersTab(),
              _buildSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersTab() {
     if (_isLoadingOrders) return const Center(child: CircularProgressIndicator());
     if (_orders.isEmpty) return const Center(child: Text("Hozircha buyurtmalar yo'q"));

     return ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          final status = order['status'] ?? 'pending';
          final isPending = status == 'pending';

          Color statusColor = Colors.grey;
          String statusText = "Kutilmoqda";
          if (status == 'approved') { statusColor = AppColors.success; statusText = "Tasdiqlangan"; }
          else if (status == 'rejected') { statusColor = AppColors.error; statusText = "Rad etilgan"; }
          else if (status == 'delivered') { statusColor = Colors.blue; statusText = "Yetkazilgan"; }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: statusColor.withOpacity(0.1), child: Icon(Icons.shopping_bag_outlined, color: statusColor)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order['branch_name'] ?? 'Filial', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("ID: #ORD-${order['id']} | ${order['created_at'].toString().substring(0, 16).replaceAll('T', ' ')}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (order['photo_file_id'] != null)
                        IconButton(
                          icon: const Icon(Icons.image, color: Colors.blue),
                          onPressed: () => _showPhotoDialog(order['photo_file_id'], order['branch_name']),
                          tooltip: "Rasmni ko'rish",
                        ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  
                  // Items List
                  if (order['items'] != null && (order['items'] as List).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.2))
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("📦 Buyurtma tarkibi:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                          const SizedBox(height: 6),
                          ...(order['items'] as List).map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.circle, size: 6, color: Colors.indigo),
                                const SizedBox(width: 8),
                                Expanded(child: Text("${item['product_name']}", style: const TextStyle(fontSize: 14))),
                                Text("${item['quantity']} ${item['unit']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isPending) ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                          onPressed: () => _showProcessOrderDialog(order, 'approved'),
                          child: const Text("Tasdiqlash")
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _showProcessOrderDialog(order, 'rejected'),
                          child: const Text("Rad etish")
                        ),
                      ] else 
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      
                      if (status == 'approved') ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.qr_code_2, color: Colors.blue),
                          onPressed: () => _showQRDialog(order['id']),
                          tooltip: "QR Kod (Xprinter uchun)",
                        ),
                      ]
                    ],
                  ),
                  if (order['admin_comment'] != null && order['admin_comment'].toString().isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 12, left: 56),
                      child: Divider(height: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 56),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.comment_outlined, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final fullComment = order['admin_comment'].toString();
                                final parts = fullComment.split('[QABUL QILISHDA KAMCHILIK]:');
                                final adminNote = parts[0].trim();
                                final issueNote = parts.length > 1 ? parts[1].trim() : null;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (adminNote.isNotEmpty)
                                      SelectableText.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(text: "👨‍💼 Admin: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                            TextSpan(text: adminNote),
                                          ]
                                        ),
                                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                                      ),
                                    
                                    if (adminNote.isNotEmpty && issueNote != null)
                                      const SizedBox(height: 4),

                                    if (issueNote != null)
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.error.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.error.withOpacity(0.3))
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: SelectableText.rich(
                                                TextSpan(
                                                  children: [
                                                    const TextSpan(text: "Filial (Kamchilik): ", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                                                    TextSpan(text: issueNote),
                                                  ]
                                                ),
                                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              }
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
     );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Bot Konfiguratsiyasi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          GlassContainer(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(labelText: "Bot Token API", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _telegramService.saveBotToken(_tokenController.text);
                        AppNotifications.showSuccess(context, "Saqlandi");
                      }, 
                      child: const Text("Tokenni saqlash")
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text("Foydalanuvchilar va Huquqlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: _showManualAddDialog, 
                icon: const Icon(Icons.add), 
                label: const Text("Qo'lda qo'shish")
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _scanForUsers, 
                icon: const Icon(Icons.person_search), 
                label: const Text("Scan (Yangi userlar)")
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_users.isEmpty) 
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: GlassContainer(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Foydalanuvchilar mavjud emas")))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _users.length,
              separatorBuilder: (c, i) => const Divider(),
              itemBuilder: (context, index) {
                final u = _users[index];
                final role = u['role'] ?? 'pending';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (role == 'admin' ? Colors.red : role == 'branch' ? Colors.blue : Colors.grey).withOpacity(0.1),
                    child: Icon(role == 'admin' ? Icons.admin_panel_settings : role == 'branch' ? Icons.store : Icons.person_outline, color: role == 'admin' ? Colors.red : role == 'branch' ? Colors.blue : Colors.grey),
                  ),
                  title: Row(
                    children: [
                      Text(u['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                        onPressed: () => _showEditNameDialog(u['chatId'], u['name']),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  subtitle: Text("ID: ${u['chatId']}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: ['admin', 'branch', 'Viewer', 'pending'].contains(role) ? role : 'pending',
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text("Admin")),
                          DropdownMenuItem(value: 'branch', child: Text("Filial")),
                          DropdownMenuItem(value: 'Viewer', child: Text("Ko'ruvchi")),
                          DropdownMenuItem(value: 'pending', child: Text("Kutmoqda")),
                        ],
                        onChanged: (val) async {
                          if (val != null) {
                            await _telegramService.updateUserRole(u['chatId'], val);
                            _loadAll();
                            if (val != 'pending') {
                               await _telegramService.sendMessage(u['chatId'], "✅ *Ruxsat berildi!* \nSizga **$val** huquqi biriktirildi. /start tugmasini bosing.");
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                           await _telegramService.deleteUser(u['chatId']);
                           _loadAll();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showProcessOrderDialog(Map<String, dynamic> order, String action) {
    final commentCtrl = TextEditingController();
    final isApprove = action == 'approved';
    
    // State for local items list
    List<Map<String, dynamic>> addedItems = [];
    
    // If approving, pre-load existing items if any (for editing existing orders not implemented, but good practice init)
    // For now we assume we are adding new items to photo orders or reviewing existing ones.
    
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental close
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(isApprove ? "Buyurtmani tasdiqlash" : "Buyurtmani rad etish"),
            content: SizedBox(
               width: 500, // Wider for product list
               child: SingleChildScrollView(
                 child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${order['branch_name']} buyurtmasi uchun ${isApprove ? 'tasdiqlash' : 'rad etish'} izohini yozishingiz mumkin:"),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: isApprove ? "Izoh (ixtiyoriy)..." : "Rad etish sababi (majburiy)...",
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    
                    if (isApprove) ...[
                       const SizedBox(height: 20),
                       const Divider(),
                       const SizedBox(height: 10),
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           const Text("📦 Buyurtma Tarkibi:", style: TextStyle(fontWeight: FontWeight.bold)),
                           TextButton.icon(
                             icon: const Icon(Icons.add_circle, color: AppColors.primary),
                             label: const Text("Mahsulot qo'shish"),
                             onPressed: () async {
                                final result = await _showProductSearchDialog();
                                if (result != null) {
                                  setState(() {
                                    addedItems.add(result);
                                  });
                                }
                             },
                           ),
                         ],
                       ),
                       const SizedBox(height: 10),
                       if (addedItems.isEmpty)
                         Container(
                           padding: const EdgeInsets.all(10),
                           decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                           child: const Text("Ro'yxat bo'sh. Agar bu foto-boyurtma bo'lsa, iltimos mahsulotlarni kiriting.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                         )
                       else
                         Container(
                           decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                           child: Column(
                             children: [
                               for (int i=0; i<addedItems.length; i++)
                                 ListTile(
                                   dense: true,
                                   title: Text(addedItems[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                   trailing: Row(
                                     mainAxisSize: MainAxisSize.min,
                                     children: [
                                       Text("${addedItems[i]['quantity']} ${addedItems[i]['unit']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                       IconButton(
                                         icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                         onPressed: () => setState(() => addedItems.removeAt(i)),
                                       )
                                     ],
                                   ),
                                 )
                             ],
                           ),
                         ),
                    ],
                  ],
                ),
               ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Bekor qilish")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApprove ? AppColors.success : AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (!isApprove && commentCtrl.text.isEmpty) {
                     AppNotifications.showError(context, "Rad etish sababini yozing!");
                     return;
                  }
      
                  // 1. Save Items if any (Only for approval)
                  if (isApprove && addedItems.isNotEmpty) {
                     await _saveOrderItems(order['id'], addedItems);
                  }
      
                  // 2. Update Status
                  await _telegramService.updateOrderStatus(
                    order['id'], 
                    action, 
                    order['chat_id'], 
                    adminComment: commentCtrl.text
                  );
                  
                  AppNotifications.showSuccess(context, isApprove ? "Tasdiqlandi" : "Rad etildi");
                  _loadAll();
                  Navigator.pop(context);
                },
                child: Text(isApprove ? "Tasdiqlash" : "Rad etish"),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _saveOrderItems(int orderId, List<Map<String, dynamic>> items) async {
    final db = await DatabaseHelper.instance.database;
    // Clear existing? No, maybe append. But for simplicity let's assume we are building it now.
    // Actually, to avoid dupes if re-editing, maybe delete old ones?
    // Let's decide: Photo orders start empty. So inserts are safe.
    
    for (var item in items) {
      await db.insert('branch_order_items', {
        'order_id': orderId,
        'product_id': item['id'],
        'product_name': item['name'],
        'quantity': item['quantity'],
        'unit': item['unit'],
      });
    }
  }

  Future<Map<String, dynamic>?> _showProductSearchDialog() async {
     String query = "";
     List<Map<String, dynamic>> results = [];
     final qtyCtrl = TextEditingController();
     
     return await showDialog<Map<String, dynamic>>(
       context: context,
       builder: (context) => StatefulBuilder(
         builder: (context, setState) {
           return AlertDialog(
             title: const Text("Mahsulot qo'shish"),
             content: SizedBox(
               width: 400,
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   TextField(
                     decoration: const InputDecoration(labelText: "Qidirish...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                     onChanged: (val) async {
                        query = val;
                        if (val.length > 1) {
                           final db = await DatabaseHelper.instance.database;
                           final res = await db.query('products', where: 'name LIKE ?', whereArgs: ['%$val%'], limit: 5);
                           setState(() => results = res);
                        }
                     },
                   ),
                   const SizedBox(height: 10),
                   if (results.isNotEmpty)
                     Container(
                       height: 150,
                       decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!)),
                       child: ListView.builder(
                         itemCount: results.length,
                         itemBuilder: (c, i) {
                           final p = results[i];
                           return ListTile(
                             title: Text(p['name']),
                             subtitle: Text("${p['unit']}"),
                             onTap: () {
                               // Select product
                               showDialog(
                                 context: context,
                                 builder: (c) => AlertDialog(
                                   title: Text("${p['name']} miqdori"),
                                   content: TextField(
                                     controller: qtyCtrl,
                                     keyboardType: TextInputType.number,
                                     autofocus: true,
                                     decoration: InputDecoration(labelText: "Miqdor (${p['unit']})"),
                                   ),
                                   actions: [
                                      ElevatedButton(
                                        onPressed: () {
                                           final qty = double.tryParse(qtyCtrl.text);
                                           if (qty != null) {
                                              Navigator.pop(c); // Close qty
                                              Navigator.pop(context, {
                                                'id': p['id'],
                                                'name': p['name'],
                                                'unit': p['unit'],
                                                'quantity': qty
                                              }); // Return result
                                           }
                                        },
                                        child: const Text("Qo'shish"),
                                      )
                                   ],
                                 )
                               );
                             },
                           );
                         },
                       ),
                     ),
                 ],
               ),
             ),
             actions: [
               TextButton(onPressed: () => Navigator.pop(context), child: const Text("Yopish")),
             ],
           );
         }
       ),
     );
  }

  void _showEditNameDialog(String chatId, String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Filial nomini tahrirlash"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: "Filial/Foydalanuvchi nomi"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Bekor qilish")),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.isNotEmpty) {
                await _telegramService.updateUserName(chatId, ctrl.text);
                _loadAll();
                Navigator.pop(c);
              }
            }, 
            child: const Text("Saqlash")
          ),
        ],
      ),
    );
  }

  void _showManualAddDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Yangi foydalanuvchi"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Ism")),
            TextField(controller: idCtrl, decoration: const InputDecoration(labelText: "Telegram Chat ID")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Bekor qilish")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && idCtrl.text.isNotEmpty) {
                await _telegramService.addUser(nameCtrl.text, idCtrl.text, 'Viewer');
                _loadAll();
                Navigator.pop(c);
              }
            }, 
            child: const Text("Qo'shish")
          ),
        ],
      ),
    );
  }

  void _scanForUsers() async {
    AppNotifications.showInfo(context, "Yangi foydalanuvchilar qidirilmoqda...");
    final updates = await _telegramService.getUpdates();
    
    if (!mounted) return;
    if (updates.isEmpty) {
      AppNotifications.showError(context, "Yangi so'rovlar topilmadi.");
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("Userni tanlang"),
        children: updates.map((u) => SimpleDialogOption(
          child: Text("${u['firstName']} (${u['username'] ?? 'No Username'})"),
          onPressed: () => Navigator.pop(c, u),
        )).toList(),
      ),
    );

    if (selected != null) {
      await _telegramService.addUser(selected['firstName'], selected['chatId'], 'Viewer');
      _loadAll();
      AppNotifications.showSuccess(context, "User qo'shildi!");
    }
  }

  void _showPhotoDialog(String? fileId, String branchName) async {
    if (fileId == null) return;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    final imageUrl = await _telegramService.getFileUrl(fileId);
    
    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (imageUrl == null) {
       AppNotifications.showError(context, "Rasmni yuklab bo'lmadi");
       return;
    }

    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(c),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: Colors.white, size: 50),
                        SizedBox(height: 10),
                        Text("Rasmni ko'rsatishda xatolik", style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "$branchName - Buyurtma qog'ozi",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQRDialog(int orderId) async {
    // Fetch bot username async
    final username = await TelegramService().getBotUsername();
    final qrData = (username != null) 
      ? "https://t.me/$username?start=confirm_$orderId"
      : "#ORD-$orderId"; // Fallback

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
            SizedBox(width: 12),
            Text("QR Kod (Kamera uchun)"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Bu kodni telefon kamerasi orqali skanerlang.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.network(
                "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=$qrData",
                width: 250,
                height: 250,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    width: 250,
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "#ORD-$orderId",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Yopish"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text("Chiqarish"),
            onPressed: () async {
              await PrintService.printOrderQR(qrData, "#ORD-$orderId");
            },
          ),
        ],
      ),
    );
  }
}
