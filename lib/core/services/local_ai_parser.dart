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
        'подпись', 'печать', 'расшифровка', 'лицо', 'директор', 'бухгалтер', 'товар', 'услуг', 'перечень'
      ];

      bool isJunk = false;
      for (var sw in stopWords) {
        if (lowerLine.contains(sw)) {
          isJunk = true;
          break;
        }
      }
      if (isJunk || line.length < 5) continue;

      // 3. Units Recognition (Russian specific)
      foundUnit = 'dona';
      final unitMap = {
        'шт': 'шт', 'шт.': 'шт', 'шт ': 'шт',
        'кг': 'кг', 'кг.': 'кг',
        'ед': 'ед', 'ед.': 'ед',
        'уп': 'уп', 'уп.': 'уп',
        'фл': 'фл', 'фл.': 'фл',
        'амп': 'амп', 'амп.': 'амп',
        'мл': 'мл', 'мл.': 'мл',
        'гр': 'гр', 'гр.': 'гр',
        'мг': 'мг', 'мг.': 'мг',
      };

      for (var entry in unitMap.entries) {
        if (lowerLine.contains(' ${entry.key} ') || lowerLine.endsWith(entry.key)) {
          foundUnit = entry.value;
          break;
        }
      }

      // 4. Numbers Extraction (Filtering years and IDs)
      final numberRegex = RegExp(r'(\d+[\d\s]*[\.,]?[\d\s]*\d+)');
      final rawMatches = numberRegex.allMatches(line).map((m) => m.group(0)!).toList();
      
      List<double> numbers = [];
      for (var m in rawMatches) {
        final cleanM = m.replaceAll(' ', '').replaceAll(',', '.');
        final n = double.tryParse(cleanM);
        if (n != null && n > 0 && n != 2024 && n != 2025 && n != 2026) {
          numbers.add(n);
        }
      }

      // 5. Pattern Logic: Most Russian invoices are Name -> Qty -> Price -> Total
      if (numbers.isNotEmpty) {
        if (numbers.length >= 3) {
           // Pattern: [Index/Other] [Qty] [Price] [Total]
           foundQty = numbers[numbers.length - 3];
           foundPrice = numbers[numbers.length - 2];
        } else if (numbers.length == 2) {
           // Pattern: [Qty] [Price]
           foundQty = numbers[0];
           foundPrice = numbers[1];
        } else {
           foundQty = numbers[0];
           foundPrice = 0.0;
        }
      }

      // 6. Database Matching - Match Product Name
      for (var product in dbProducts) {
        final pName = product['name'].toString().toLowerCase();
        if (lowerLine.contains(pName)) {
          foundProductName = product['name'];
          foundProductId = product['id'];
          foundUnit = product['unit'];
          break; 
        }
      }

      // 7. If not in DB, extract name cleanly from the start of the line
      if (foundProductName == null && numbers.isNotEmpty) {
          // Take the part before the first number as the name
          final firstDigitIdx = line.indexOf(RegExp(r'\d'));
          if (firstDigitIdx > 3) {
            foundProductName = line.substring(0, firstDigitIdx).trim();
            // Remove starting junk like "1." or "2)"
            foundProductName = foundProductName.replaceAll(RegExp(r'^\d+[\s\.\)]+'), '').trim();
          }
      }

      // 8. Resulting Row
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
