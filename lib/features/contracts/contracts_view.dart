import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../core/services/contract_service.dart';
import '../../core/widgets/glass_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/contract_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_translations.dart';

class ContractsView extends StatefulWidget {
  const ContractsView({super.key});

  @override
  State<ContractsView> createState() => _ContractsViewState();
}

enum ContractViewLevel { organizations, companies, files }

class _ContractsViewState extends State<ContractsView> {
  final ContractService _contractService = ContractService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Contract> _allContracts = [];
  bool _isLoading = true;
  String _searchQuery = "";

  // Navigation state
  ContractViewLevel _currentLevel = ContractViewLevel.organizations;
  String? _selectedOurOrg;
  String? _selectedPartner;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  Future<void> _loadContracts() async {
    setState(() => _isLoading = true);
    try {
      final data = await _contractService.getAllContracts();
      setState(() {
        _allContracts = data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Contracts load error: $e");
      setState(() => _isLoading = false);
    }
  }

  List<String> get _organizations {
    final orgs = _allContracts
        .map((e) => e.ourOrganization)
        .toSet()
        .toList();
    orgs.sort();
    return orgs;
  }

  List<String> get _partners {
    if (_selectedOurOrg == null) return [];
    final partners = _allContracts
        .where((e) => e.ourOrganization == _selectedOurOrg)
        .map((e) => e.companyName)
        .toSet()
        .toList();
    partners.sort();
    return partners;
  }

  List<Contract> get _visibleContracts {
    var filtered = _allContracts;
    
    if (_selectedOurOrg != null) {
      filtered = filtered.where((e) => e.ourOrganization == _selectedOurOrg).toList();
    }
    
    if (_selectedPartner != null) {
      filtered = filtered.where((e) => e.companyName == _selectedPartner).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((c) => 
        c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c.companyName.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    return filtered;
  }

  void _goBack() {
    setState(() {
      if (_currentLevel == ContractViewLevel.files) {
        _currentLevel = ContractViewLevel.companies;
        _selectedPartner = null;
      } else if (_currentLevel == ContractViewLevel.companies) {
        _currentLevel = ContractViewLevel.organizations;
        _selectedOurOrg = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildCustomHeader(),
            _buildStatsBar(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.4),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.6)),
                ),
                child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : _buildDynamicContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentLevel != ContractViewLevel.organizations)
          _buildBreadcrumbs(),
        const SizedBox(height: 16),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _getSelectedGrid(),
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: _goBack,
          tooltip: "Orqaga",
        ),
        const SizedBox(width: 8),
        Text(
          _selectedOurOrg ?? "",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (_selectedPartner != null) ...[
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          Text(
            _selectedPartner!,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
          ),
        ],
      ],
    );
  }

  Widget _getSelectedGrid() {
    if (_currentLevel == ContractViewLevel.organizations) {
      if (_organizations.isEmpty) return _buildEmptyState();
      return _buildFolderGrid(_organizations, isPartner: false);
    } else if (_currentLevel == ContractViewLevel.companies) {
      return _buildFolderGrid(_partners, isPartner: true);
    } else {
      return _buildFilesGrid();
    }
  }

  Widget _buildFolderGrid(List<String> items, {required bool isPartner}) {
    return GridView.builder(
      key: ValueKey("${_currentLevel.name}_grid"),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 0.9,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final name = items[index];
        final count = isPartner 
          ? _allContracts.where((e) => e.ourOrganization == _selectedOurOrg && e.companyName == name).length
          : _allContracts.where((e) => e.ourOrganization == name).length;

        return _FolderCard(
          name: name,
          count: count,
          isLevel2: isPartner,
          onTap: () {
            setState(() {
              if (!isPartner) {
                _selectedOurOrg = name;
                _currentLevel = ContractViewLevel.companies;
              } else {
                _selectedPartner = name;
                _currentLevel = ContractViewLevel.files;
              }
            });
          },
          onEdit: () => _showRenameDialog(name, isPartner),
          onDelete: () => _confirmDeleteFolder(name, isPartner),
        );
      },
    );
  }

  Widget _buildFilesGrid() {
    final contracts = _visibleContracts;
    if (contracts.isEmpty) return _buildEmptyState();

    return GridView.builder(
      key: const ValueKey("files_grid"),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 0.85,
      ),
      itemCount: contracts.length,
      itemBuilder: (context, index) {
        final contract = contracts[index];
        return _FileCard(
          contract: contract,
          onTap: () => _showFileDetails(contract),
          onDelete: () => _confirmDeleteFile(contract),
          onEdit: () => _showEditFilePicker(contract),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final t = Provider.of<AppTranslations>(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(t.text('msg_no_data'), style: const TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCustomHeader() {
    final t = Provider.of<AppTranslations>(context);
    return GlassTopBar(
      title: t.text('menu_contracts'),
      subtitle: t.text('contracts_subtitle'),
      actions: [
        Container(
          width: 200,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: t.text('search_hint'),
              hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.4), fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: AppColors.textPrimary.withValues(alpha: 0.4)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GlassButton(
          label: t.text('contracts_btn_upload'),
          icon: Icons.upload_file_rounded,
          style: GlassButtonStyle.primary,
          onTap: _uploadNewContract,
        ),
        GlassButton(
          label: t.text('contracts_btn_refresh'),
          icon: Icons.refresh_rounded,
          onTap: _loadContracts,
        ),
      ],
    );
  }

  Widget _buildStatsBar() {
    final t = Provider.of<AppTranslations>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          _StatChip(icon: Icons.business_rounded, label: "${_organizations.length} ${t.text('contracts_unit_org')}"),
          const SizedBox(width: 16),
          _StatChip(icon: Icons.handshake_rounded, label: "${_allContracts.map((e)=>e.companyName).toSet().length} ${t.text('contracts_unit_partner')}"),
          const SizedBox(width: 16),
          _StatChip(icon: Icons.description_rounded, label: "${_allContracts.length} ${t.text('contracts_unit_pdf')}"),
        ],
      ),
    );
  }

  Future<void> _showFileDetails(Contract contract) async {
    if (contract.fileUrl == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contract.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text("${contract.ourOrganization} ➔ ${contract.companyName}", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // PDF Preview & Body
              Expanded(
                child: Row(
                  children: [
                    // Preview
                    Expanded(
                      flex: 3,
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: PdfPreview(
                          build: (format) => _fetchPdfBytes(contract.fileUrl!),
                          allowPrinting: false,
                          allowSharing: false,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false,
                        ),
                      ),
                    ),
                    // Actions right panel
                    Container(
                      width: 250,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text("AMALLAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey, letterSpacing: 1.2)),
                          const SizedBox(height: 16),
                          _buildActionTile(icon: Icons.print_rounded, label: "Chop etish", color: Colors.blue, onTap: () => _printPdf(contract)),
                          _buildActionTile(icon: Icons.download_rounded, label: "Yuklab olish", color: Colors.green, onTap: () => _downloadPdf(contract)),
                          _buildActionTile(icon: Icons.share_rounded, label: "Ulashish", color: Colors.orange, onTap: () => _sharePdf(contract)),
                          _buildActionTile(icon: Icons.open_in_browser_rounded, label: "Brauzerda ochish", color: Colors.grey, onTap: () => launchUrl(Uri.parse(contract.fileUrl!))),
                          const Spacer(),
                          const Divider(),
                          _buildActionTile(icon: Icons.edit_rounded, label: "Tahrirlash", color: AppColors.primary, onTap: () {
                            Navigator.pop(context);
                            _showEditFilePicker(contract);
                          }),
                          _buildActionTile(icon: Icons.delete_rounded, label: "O'chirish", color: Colors.red, onTap: () {
                            Navigator.pop(context);
                            _confirmDeleteFile(contract);
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.1)),
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(String oldName, bool isPartner) async {
    final controller = TextEditingController(text: oldName);
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isPartner ? 'Firma' : 'Tashkilot'} nomini o\'zgartirish'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Yangi nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor qilish')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isEmpty || controller.text == oldName) return;
              Navigator.pop(context, true);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        if (!isPartner) {
          await _contractService.renameOrganization(oldName, controller.text);
        } else {
          await _contractService.renamePartner(_selectedOurOrg!, oldName, controller.text);
        }
        await _loadContracts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("O'zgartirishda xatolik: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDeleteFolder(String name, bool isPartner) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isPartner ? 'Firmani' : 'Tashkilotni'} o\'chirish'),
        content: Text('Haqiqatan ham "$name" va uning ichidagi BARCHA hujjatlarni o\'chirmoqchimisiz? Bu amalni ortga qaytarib bo\'lmaydi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor qilish')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ha, o\'chirilsin', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        if (!isPartner) {
          await _contractService.deleteOrganization(name);
        } else {
          await _contractService.deletePartner(_selectedOurOrg!, name);
        }
        await _loadContracts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("O'chirishda xatolik: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDeleteFile(Contract contract) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hujjatni o\'chirish'),
        content: Text('"${contract.name}" hujjatini o\'chirmoqchimisiz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Yo\'q')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ha', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await _contractService.deleteContract(contract.id);
        await _loadContracts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("O'chirishda xatolik: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showEditFilePicker(Contract contract) async {
    final nameController = TextEditingController(text: contract.name);
    final partnerController = TextEditingController(text: contract.companyName);
    final orgController = TextEditingController(text: contract.ourOrganization);

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hujjatni tahrirlash'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Hujjat nomi')),
            TextField(controller: partnerController, decoration: const InputDecoration(labelText: 'Hamkor firma')),
            TextField(controller: orgController, decoration: const InputDecoration(labelText: 'Bizning tashkilot')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor qilish')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Saqlash')),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await _contractService.updateContract(contract.id, {
          'name': nameController.text,
          'company_name': partnerController.text,
          'our_organization': orgController.text,
        });
        await _loadContracts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppTranslations().text('msg_error')}: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }
  Future<void> _uploadNewContract() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    if (!mounted) return;

    String? ourOrg = _selectedOurOrg;
    String? partner = _selectedPartner;
    final nameController = TextEditingController(text: fileName);
    final ourOrgController = TextEditingController();
    final partnerController = TextEditingController();

    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: GlassContainer(
            width: 450,
            padding: const EdgeInsets.all(32),
            borderRadius: 30,
            opacity: 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary),
                      ),
                      const SizedBox(width: 16),
                      Text(AppTranslations().text('contracts_btn_upload'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  _buildLabel(AppTranslations().text('label_reagent')),
                  _buildCustomTextField(controller: nameController, hint: AppTranslations().text('label_reagent')),
                  
                  const SizedBox(height: 20),
                  _buildLabel(AppTranslations().text('contracts_lbl_our_org')),
                  _buildCustomDropdown(
                    value: ourOrg,
                    items: [
                      ..._organizations.map((o) => DropdownMenuItem(value: o, child: Text(o))),
                      DropdownMenuItem(value: 'NEW', child: Text('+ ${AppTranslations().text('contracts_add_org')}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) => setDialogState(() => ourOrg = val),
                  ),
                  if (ourOrg == 'NEW') ...[
                    const SizedBox(height: 12),
                    _buildCustomTextField(controller: ourOrgController, hint: AppTranslations().text('contracts_hint_new_org')),
                  ],

                  const SizedBox(height: 20),
                  _buildLabel(AppTranslations().text('contracts_lbl_partner')),
                  _buildCustomDropdown(
                    value: ourOrg == 'NEW' ? null : partner,
                    items: [
                      ..._partners.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                      DropdownMenuItem(value: 'NEW_PARTNER', child: Text('+ ${AppTranslations().text('contracts_add_partner')}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) => setDialogState(() => partner = val),
                  ),
                  if (partner == 'NEW_PARTNER') ...[
                    const SizedBox(height: 12),
                    _buildCustomTextField(controller: partnerController, hint: AppTranslations().text('contracts_hint_new_partner')),
                  ],

                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(AppTranslations().text('btn_cancel'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      GlassButton(
                        label: AppTranslations().text('contracts_btn_upload'),
                        icon: Icons.check_rounded,
                        style: GlassButtonStyle.primary,
                        onTap: () {
                          if ((ourOrg == null && (ourOrg == 'NEW' && ourOrgController.text.isEmpty)) || 
                              (partner == null && (partner == 'NEW_PARTNER' && partnerController.text.isEmpty))) {
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final finalOurOrg = ourOrg == 'NEW' ? ourOrgController.text : (ourOrg ?? ourOrgController.text);
      final finalPartner = partner == 'NEW_PARTNER' ? partnerController.text : (partner ?? partnerController.text);
      
      setState(() => _isLoading = true);
      try {
        await _contractService.uploadContract(file, nameController.text, finalPartner, finalOurOrg);
        await _loadContracts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xatolik: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCustomTextField({required TextEditingController controller, required String hint}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.2))),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCustomDropdown({required String? value, required List<DropdownMenuItem<String>> items, required Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.2))),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: Colors.white.withValues(alpha: 1.0),
          borderRadius: BorderRadius.circular(20),
          decoration: const InputDecoration(border: InputBorder.none),
          style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // --- Helper Methods for PDF Actions ---
  Future<Uint8List> _fetchPdfBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) return Uint8List.fromList(response.bodyBytes);
    throw Exception("Failed to load PDF");
  }

  Future<void> _printPdf(Contract contract) async {
    final bytes = await _fetchPdfBytes(contract.fileUrl!);
    await Printing.layoutPdf(onLayout: (format) => bytes);
  }

  Future<void> _sharePdf(Contract contract) async {
    final bytes = await _fetchPdfBytes(contract.fileUrl!);
    final tempDir = await getTemporaryDirectory();
    final file = File("${tempDir.path}/${contract.name}.pdf");
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: contract.name));
  }

  Future<void> _downloadPdf(Contract contract) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    
    final bytes = await _fetchPdfBytes(contract.fileUrl!);
    final file = File("$result/${contract.name}.pdf");
    await file.writeAsBytes(bytes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hujjat saqlandi: ${file.path}")));
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final int count;
  final bool isLevel2;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FolderCard({
    required this.name, 
    required this.count, 
    required this.isLevel2, 
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GlassContainer(
            borderRadius: 20,
            opacity: 0.1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isLevel2 ? Icons.folder_shared_rounded : Icons.business_center_rounded, 
                        size: 56, 
                        color: isLevel2 ? Colors.orange : AppColors.primary
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLevel2 ? "$count ta PDF" : "$count ta firma",
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.transparent,
              type: MaterialType.circle,
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Nomni o\'zgartirish')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: Colors.red), SizedBox(width: 8), Text('O\'chirish', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final Contract contract;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _FileCard({required this.contract, required this.onTap, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GlassContainer(
            borderRadius: 20,
            opacity: 0.15,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.picture_as_pdf_rounded, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 8),
                              Text(
                                contract.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                      Text(
                        DateFormat('dd.MM.yy').format(contract.createdAt),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.transparent,
              type: MaterialType.circle,
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Tahrirlash')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: Colors.red), SizedBox(width: 8), Text('O\'chirish', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
