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
      bool isJunkLine = false;
      final junkKeywords = [
        'счет', 'номер', 'дата', 'итого', 'сумма', 'акциз', 'всего', 'область', 'город', 'инн',
        'адрис', 'телефон', 'mfo', 'bank', 'ru-ru', 'en-us', 'поставщик', 'заказчик', '2023', '2024', '2025', '2026',
        'четыре', 'миллион', 'оплатить', 'наиме', 'без ', 'на опл'
      ];

      for (var keyword in junkKeywords) {
        if (line.toLowerCase().contains(keyword)) {
          isJunkLine = true;
          break;
        }
      }

      if (isJunkLine) continue;

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
          final cleanM = m.replaceAll(',', '.');
          final n = double.tryParse(cleanM);
          // Yillarni va kichik idlarni filtrlash (masalan 2024-2026 larni o'tkazib yubormaslik uchun)
          if (n != null && n > 0 && n != 2024 && n != 2025 && n != 2026) {
            numbers.add(n);
          }
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
          foundPrice = 0.0;
        }
      }

      // 4. Capture hatto bazada yo'q bo'lsa ham
      if (foundProductName == null && numbers.isNotEmpty && line.length > 5) {
        // Matndan keraksiz narsalarni tozalaymiz
        final nameCandidate = line
            .replaceAll(RegExp(r'\d+[\.,]?\d*'), '') // Raqamlarni o'chiramiz
            .replaceAll(RegExp(r'[^\w\sа-яА-ЯёЁ\-]'), '') // Maxsus belgilarni o'chiramiz
            .trim();
            
        if (nameCandidate.length > 3) {
          foundProductName = nameCandidate;
        }
      }

      // 5. Faqat shubhali bo'lmagan ma'lumotlarni qo'shamiz
      if (foundProductName != null && (foundQty != null || foundPrice != null)) {
        // Agar miqdor juda katta bo'lsa (masalan 1000000), uni miqdor emas narx deb bilsin
        if (foundQty != null && foundQty > 10000 && (foundPrice == null || foundPrice == 0)) {
           foundPrice = foundQty;
           foundQty = 1.0;
        }

        results.add({
          "name": foundProductName,
          "id": foundProductId,
          "unit": foundUnit ?? 'dona',
          "quantity": foundQty ?? 1.0,
          "price": foundPrice ?? 0.0,
          "is_new": foundProductId == null,
        });
      }
    }

    return results;
  }
}
