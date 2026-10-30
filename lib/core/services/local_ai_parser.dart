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

      final lowerLine = line.toLowerCase();
      
      // 1. Junk Filters 
      // Faqat qatorni butunlay bekor qiladigan so'zlar
      final skipLinesContaining = [
        'счет на оплату', 'итого:', 'в том числе', 'всего к оплате', 
        'всего наименований', 'оплатить не позднее', 'банк получателя', 
        'поставщик (исполнитель)', 'покупатель (заказчик)', 'основание:'
      ];
      
      bool isJunk = false;
      for (var sw in skipLinesContaining) {
        if (lowerLine.contains(sw)) {
          isJunk = true;
          break;
        }
      }

      // Sarlavha (Header) qatorini o'tkazib yuborish
      if (lowerLine.contains('товары (работы, услуги)') && lowerLine.contains('кол-во')) {
         isJunk = true;
      }
      if (lowerLine.contains('ставка') && lowerLine.contains('сумма')) {
         isJunk = true;
      }
      
      // Filtrlash: Agar qatorda juda uzun raqamlar bo'lsa (bank hisob raqami kabi INN, MFO)
      if (lowerLine.contains('инн') || lowerLine.contains('мфо') || lowerLine.contains('сч. nº')) isJunk = true;

      if (isJunk || line.length < 5) continue;

      // 2. Units Recognition
      bool hasUnit = false;
      foundUnit = 'dona';
      final unitMap = {
        'шт': 'шт', 'шт.': 'шт', 'кг': 'кг', 'ед': 'ед', 'уп': 'уп', 
        'фл': 'фл', 'амп': 'амп', 'мл': 'мл', 'гр': 'гр', 'мг': 'мг',
      };

      for (var entry in unitMap.entries) {
        final reg = RegExp('\\s${entry.key}(\\s|\\.|\\,)\$|\\s${entry.key}(\\s|\\,|\\.)');
        if (lowerLine.contains(reg) || lowerLine.endsWith(entry.key)) {
          foundUnit = entry.value;
          hasUnit = true;
          break;
        }
      }

      // 3. Numbers Extraction 
      // Hamma raqamlarni (shu jumladan bitta xonali "1", "2") olamiz va bitta arrayga yig'amiz.
      // Probel bilan kelgan (masalan 1 619 000) narxlarni avval tozalaymiz.
      // Oddiy so'zlardan ajratib olamiz.
      final numberRegex = RegExp(r'\b\d+(?:[\s\.,]\d+)*(?:[,.]\d+)?\b');
      final rawMatches = numberRegex.allMatches(line).map((m) => m.group(0)!).toList();
      
      List<double> numbers = [];
      for (var m in rawMatches) {
        // "1 619 000,00" -> "1619000.00"
        final cleanM = m.replaceAll(' ', '').replaceAll(',', '.');
        final n = double.tryParse(cleanM);
        
        // Yillarni olib tashlaymiz
        if (n != null && n > 0 && n != 2024 && n != 2025 && n != 2026 && n != 12) {
          numbers.add(n);
        }
      }

      // 4. Pattern Logic: Mixplus Med Table Structure
      // [Index] [Product Name Description] [Qty] [Unit] [Price] [Sum] [VAT...]
      if (numbers.isNotEmpty) {
        if (numbers.length >= 3) {
            // [0] odatda tartib raqami (Index)
            // [1] odatda miqdor (Qty)
            // [2] odatda narx (Price)
            // Ammo ehtiyotkor bo'lamiz: agar Index topilmasa, Qty [0] bo'ladi.
            foundQty = (numbers.length > 2) ? numbers[1] : numbers[0];
            foundPrice = (numbers.length > 2) ? numbers[2] : numbers[1];
        } else if (numbers.length == 2) {
            foundQty = numbers[0];
            foundPrice = numbers[1];
        } else {
            foundQty = numbers[0];
            foundPrice = 0.0;
        }
      }

      // 5. DB Match (Highest priority)
      for (var product in dbProducts) {
        final pName = product['name'].toString().toLowerCase();
        if (lowerLine.contains(pName)) {
          foundProductName = product['name'];
          foundProductId = product['id'];
          foundUnit = product['unit'];
          break; 
        }
      }

      // 6. Strict Name Extraction for new items
      if (foundProductName == null && numbers.isNotEmpty && hasUnit) {
          // Birlik topilgan bo'lsa, satrdan tartib raqamini chetlab, Nomini qirqib olamiz.
          final matches = RegExp(r'^\s*\d+').allMatches(line); // Tartib raqami
          int nameStart = matches.isNotEmpty ? matches.first.end : 0;

          // Ism tugash qismi: birlik (шт) dan oldingi raqam (miqdor) kelgan joy
          int nameEnd = line.length;
          final digitMatches = RegExp(r'\d').allMatches(line);
          for (var dm in digitMatches) {
            if (dm.start > nameStart + 5) {
               nameEnd = dm.start;
               break;
            }
          }

          if (nameEnd > nameStart) {
            String candidate = line.substring(nameStart, nameEnd).trim();
            candidate = candidate.replaceAll(RegExp(r'[:;,.]$'), '').trim();
            if (candidate.length > 3) {
              foundProductName = candidate;
            }
          }
      }

      // 7. Faqat haqiqiy mahsulotlarni jadvalga yozish
      if (foundProductName != null && foundProductName.length > 2 && (foundQty ?? 0) > 0) {
        results.add({
          "name": foundProductName,
          "id": foundProductId,
          "unit": foundUnit,
          "quantity": foundQty ?? 1.0,
          "price": foundPrice ?? 0.0,
          "is_new": foundProductId == null,
        });
      }
    }

    return results;
  }
}
