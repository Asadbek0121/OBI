import 'package:clinical_warehouse/core/database/database_helper.dart';

class LocalAIParser {
  // Bu funksiya xom matnni (text) oladi va uni bazadagi mahsulotlar bilan solishtirib,
  // jadval ko'rinishiga keltiradi.
  static Future<List<Map<String, dynamic>>> parseUsingDatabase(String rawText) async {
    final List<Map<String, dynamic>> results = [];
    
    // 1. Bazadagi barcha faol mahsulotlarni olib kelamiz
    final dbProducts = await DatabaseHelper.instance.getAllProducts();
    
    // Matnni qatorlarga bo'lamiz
    final lines = rawText.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

    for (var line in lines) {
      String? foundProductName;
      int? foundProductId;
      String? foundUnit;
      double? foundQty;
      double? foundPrice;

      // 2. Har bir qatorda bazadagi mahsulot nomini qidiramiz (Intellektual qidiruv)
      for (var product in dbProducts) {
        final pName = product['name'].toString().toLowerCase();
        final lText = line.toLowerCase();
        
        // Agar qatorda mahsulot nomi bo'lsa yoki nomi qismat bo'lsa
        if (lText.contains(pName) || pName.contains(lText)) {
          foundProductName = product['name'];
          foundProductId = product['id'];
          foundUnit = product['unit'];
          break; 
        }
      }

      // 3. Raqamlarni aniqlaymiz (Miqdor va Narx)
      final numberRegex = RegExp(r'(\d+[\.,]?\d*)');
      final matches = numberRegex.allMatches(line).map((m) => m.group(0)).toList();
      
      List<double> numbers = [];
      for (var m in matches) {
        if (m != null) {
          final n = double.tryParse(m.replaceAll(',', '.'));
          if (n != null) numbers.add(n);
        }
      }

      // Heuristika: Katta raqam - narx, kichikroq raqam - miqdor
      if (numbers.isNotEmpty) {
        if (numbers.length >= 2) {
          numbers.sort(); // Kichigidan kattasiga
          foundQty = numbers[0];
          foundPrice = numbers[numbers.length - 1];
        } else {
          foundQty = numbers[0];
        }
      }

      // Faqatgina mahsulot topilsa qo'shamiz
      if (foundProductName != null) {
        results.add({
          "name": foundProductName,
          "id": foundProductId,
          "unit": foundUnit ?? 'dona',
          "quantity": foundQty ?? 1.0,
          "price": foundPrice ?? 0.0,
        });
      }
    }

    return results;
  }
}
