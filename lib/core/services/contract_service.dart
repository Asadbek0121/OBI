import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import '../database/database_helper.dart';
import '../models/contract_model.dart';
import 'package:uuid/uuid.dart';

class ContractService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Supabase-dagi bucket nomi
  static const String _bucketName = 'contracts';

  /// 1. Yangi shartnomani yuklash (Upload)
  Future<Contract> uploadContract(File file, String name, String companyName, String ourOrganization) async {
    final id = const Uuid().v4();
    final fileExtension = p.extension(file.path);
    final fileName = '$id$fileExtension';

    // A. Supabase Storage-ga yuklash
    await _supabase.storage
        .from(_bucketName)
        .upload(fileName, file);

    // B. Public URL olish
    final String fileUrl = _supabase.storage.from(_bucketName).getPublicUrl(fileName);

    final contract = Contract(
      id: id,
      name: name,
      companyName: companyName,
      ourOrganization: ourOrganization,
      fileUrl: fileUrl,
      localPath: file.path, 
      status: 'synced',
      createdAt: DateTime.now(),
    );

    // C. Supabase Database-ga saqlash
    await _supabase.from('contracts').insert(contract.toJson());

    // D. Lokal SQLite-ga saqlash
    final db = await _dbHelper.database;
    await db.insert('contracts', contract.toJson());

    return contract;
  }

  /// 2. Barcha shartnomalarni olish (Sync)
  Future<List<Contract>> getAllContracts() async {
    try {
      final response = await _supabase
          .from('contracts')
          .select()
          .order('created_at', ascending: false);

      final contracts = (response as List).map((e) => Contract.fromJson(e)).toList();
      return contracts;
    } catch (e) {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query('contracts', orderBy: 'created_at DESC');
      return maps.map((e) => Contract.fromJson(e)).toList();
    }
  }

  /// 3. Shartnomani o'chirish
  Future<void> deleteContract(String id) async {
    try {
      final db = await _dbHelper.database;
      await db.delete('contracts', where: 'id = ?', whereArgs: [id]);
      await _supabase.from('contracts').delete().eq('id', id);
    } catch (e) {
      rethrow;
    }
  }

  /// 4. Shartnomani tahrirlash
  Future<void> updateContract(String id, Map<String, dynamic> updates) async {
    try {
      final db = await _dbHelper.database;
      await db.update('contracts', updates, where: 'id = ?', whereArgs: [id]);
      await _supabase.from('contracts').update(updates).eq('id', id);
    } catch (e) {
      rethrow;
    }
  }

  /// 5. Tashkilotni nomini o'zgartirish (Bulk Rename)
  Future<void> renameOrganization(String oldName, String newName) async {
    final updates = {'our_organization': newName};
    final db = await _dbHelper.database;
    
    // Robust local update
    bool isUnknown = oldName == "Noma'lum tashkilot";
    String whereClause = isUnknown ? "(our_organization = ? OR our_organization IS NULL)" : "our_organization = ?";
    await db.update('contracts', updates, where: whereClause, whereArgs: [oldName]);
    
    // Supabase update
    if (isUnknown) {
      await _supabase.from('contracts').update(updates).or('our_organization.eq.$oldName,our_organization.is.null');
    } else {
      await _supabase.from('contracts').update(updates).eq('our_organization', oldName);
    }
  }

  /// 6. Tashkilotni o'chirish (Bulk Delete)
  Future<void> deleteOrganization(String orgName) async {
    final db = await _dbHelper.database;
    
    bool isUnknown = orgName == "Noma'lum tashkilot";
    String whereClause = isUnknown ? "(our_organization = ? OR our_organization IS NULL)" : "our_organization = ?";
    await db.delete('contracts', where: whereClause, whereArgs: [orgName]);
    
    if (isUnknown) {
      await _supabase.from('contracts').delete().or('our_organization.eq.$orgName,our_organization.is.null');
    } else {
      await _supabase.from('contracts').delete().eq('our_organization', orgName);
    }
  }

  /// 7. Hamkor firmani nomini o'zgartirish (Bulk Rename)
  Future<void> renamePartner(String ourOrg, String oldName, String newName) async {
    final updates = {'company_name': newName};
    final db = await _dbHelper.database;
    
    bool isUnknown = oldName == "Noma'lum hamkor";
    String whereClause = isUnknown 
        ? "our_organization = ? AND (company_name = ? OR company_name IS NULL)"
        : "our_organization = ? AND company_name = ?";
    
    await db.update('contracts', updates, where: whereClause, whereArgs: [ourOrg, oldName]);
    
    if (isUnknown) {
      await _supabase.from('contracts').update(updates).eq('our_organization', ourOrg).or('company_name.eq.$oldName,company_name.is.null');
    } else {
      await _supabase.from('contracts').update(updates).eq('our_organization', ourOrg).eq('company_name', oldName);
    }
  }

  /// 8. Hamkor firmani o'chirish (Bulk Delete)
  Future<void> deletePartner(String ourOrg, String partnerName) async {
    final db = await _dbHelper.database;
    
    bool isUnknown = partnerName == "Noma'lum hamkor";
    String whereClause = isUnknown 
        ? "our_organization = ? AND (company_name = ? OR company_name IS NULL)"
        : "our_organization = ? AND company_name = ?";
        
    await db.delete('contracts', where: whereClause, whereArgs: [ourOrg, partnerName]);
    
    if (isUnknown) {
      await _supabase.from('contracts').delete().eq('our_organization', ourOrg).or('company_name.eq.$partnerName,company_name.is.null');
    } else {
      await _supabase.from('contracts').delete().eq('our_organization', ourOrg).eq('company_name', partnerName);
    }
  }
}
