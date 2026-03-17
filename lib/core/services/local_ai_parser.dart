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

      // 2. Junk Filters (Strict for Russian Invoices)
      final lowerLine = line.toLowerCase();
      final stopWords = [
        'счет', 'номер', 'дата', 'итого', 'сумма', 'акциз', 'всего', 'поставщик', 'плательщик', 'адрес', 'тел',
        'инн', 'мфо', 'оплата', 'наиме', 'кол-в', 'цена', 'ед.', 'изм', 'код', 'статус', 'страна', 'гтд', 'ндс',
        'подпись', 'печать', 'расшифровка', 'лицо', 'директор', 'бухгалтер', 'товар', 'услуг', 'перечень',
        'заказчик', 'основание', 'оплатить', 'грузополучатель', 'грузоотправитель', 'покупатель', 'продавец',
        'доверенность', 'через', 'документ', 'товарная', 'накладная', 'упд'
      ];

      bool isJunk = false;
      for (var sw in stopWords) {
        if (lowerLine.contains(sw)) {
          isJunk = true;
          break;
        }
      }
      
      // Filtrlash: Agar qatorda juda uzun raqamlar bo'lsa (bank hisob raqami kabi)
      if (RegExp(r'\d{10,}').hasMatch(line.replaceAll(' ', ''))) isJunk = true;

      if (isJunk || line.length < 5) continue;

      // 3. Units Recognition (Russian specific)
      bool hasUnit = false;
      foundUnit = 'dona';
      final unitMap = {
        'шт': 'шт', 'шт.': 'шт', 'кг': 'кг', 'ед': 'ед', 'уп': 'уп', 
        'фл': 'фл', 'амп': 'амп', 'мл': 'мл', 'гр': 'гр', 'мг': 'мг',
        'литр': 'л', 'блок': 'блок', 'короб': 'кор'
      };

      for (var entry in unitMap.entries) {
        // Must be a separate word or at the end
        final reg = RegExp('\\s${entry.key}(\\s|\\.|\\,)\$|\\s${entry.key}(\\s|\\.|\\,)');
        if (lowerLine.contains(reg) || lowerLine.endsWith(entry.key)) {
          foundUnit = entry.value;
          hasUnit = true;
          break;
        }
      }

      // 4. Numbers Extraction
      final numberRegex = RegExp(r'(\d+[\d\s]*[\.,к]?[\d\s]*\d+)');
      final rawMatches = numberRegex.allMatches(line).map((m) => m.group(0)!).toList();
      
      List<double> numbers = [];
      for (var m in rawMatches) {
        final cleanM = m.replaceAll(' ', '').replaceAll(',', '.').replaceAll('к', '.');
        final n = double.tryParse(cleanM);
        if (n != null && n > 0 && n != 2023 && n != 2024 && n != 2025 && n != 2026 && n < 1000000000) {
          numbers.add(n);
        }
      }

      // 5. Database Matching (The most reliable way)
      for (var product in dbProducts) {
        final pName = product['name'].toString().toLowerCase();
        // Exact match or very close match
        if (lowerLine.contains(pName)) {
          foundProductName = product['name'];
          foundProductId = product['id'];
          foundUnit = product['unit'];
          break; 
        }
      }

      // 6. If not in DB, extract name STRICTLY
      if (foundProductName == null && numbers.isNotEmpty) {
          // A line that isn't in DB MUST have a recognized UNIT to be valid
          // This prevents address lines or other metadata from being treated as products
          if (hasUnit || numbers.length >= 2) {
              final firstDigitIdx = line.indexOf(RegExp(r'\d'));
              if (firstDigitIdx > 3) {
                String potentialName = line.substring(0, firstDigitIdx).trim();
                potentialName = potentialName.replaceAll(RegExp(r'^\d+[\s\.\)]+'), '').trim();
                potentialName = potentialName.replaceAll(RegExp(r'[:;,.]$'), '').trim();
                
                if (potentialName.length > 3) {
                  foundProductName = potentialName;
                }
              }
          }
      }

      // 7. Pattern Logic for Qty/Price
      if (numbers.isNotEmpty) {
        if (numbers.length >= 3) {
           foundQty = numbers[numbers.length - 3];
           foundPrice = numbers[numbers.length - 2];
        } else if (numbers.length == 2) {
           foundQty = numbers[0];
           foundPrice = numbers[1];
        } else {
           foundQty = numbers[0];
           foundPrice = 0.0;
        }
      }

      // 8. Resulting Row - Double check if it's not a junk name
      if (foundProductName != null && foundProductName.length > 2 && (foundQty ?? 0) > 0) {
        // Last-minute check for stop words in the extracted name itself
        bool nameIsJunk = false;
        for (var sw in stopWords) {
          if (foundProductName.toLowerCase().contains(sw)) {
            nameIsJunk = true;
            break;
          }
        }
        
        if (!nameIsJunk) {
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
    }

    return results;
  }
}
