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

      // 2. Junk Filters (Strict for Mixplus Med style invoices)
      final lowerLine = line.toLowerCase();
      final stopWords = [
        'счет', 'номер', 'дата', 'итого', 'сумма', 'акциз', 'всего', 'поставщик', 'плательщик', 'адрес', 'тел',
        'инн', 'мфо', 'оплата', 'наиме', 'кол-во', 'цена', 'ед.', 'изм', 'код', 'статус', 'страна', 'гтд', 'ндс',
        'ставка', 'подпись', 'печать', 'расшифровка', 'лицо', 'директор', 'бухгалтер', 'товар', 'услуг', 'перечень',
        'заказчик', 'основание', 'оплатить', 'грузополучатель', 'грузоотправитель', 'покупатель', 'продавец',
        'доверенность', 'через', 'документ', 'товарная', 'накладная', 'упд', 'миллион', 'тысяч', 'на сумму', 'наименований'
      ];

      bool isJunk = false;
      for (var sw in stopWords) {
        if (lowerLine.contains(sw)) {
          isJunk = true;
          break;
        }
      }
      
      // Skip lines with massive IDs (like accounts)
      if (RegExp(r'\d{12,}').hasMatch(line.replaceAll(' ', ''))) isJunk = true;
      if (isJunk || line.length < 5) continue;

      // 3. Units Recognition (Specific list from document)
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

      // 4. Numbers Extraction (Handles spaces like "1 619 000,00")
      final numberRegex = RegExp(r'(\d+[\d\s]*[\.,]?[\d\s]*\d+)');
      final rawMatches = numberRegex.allMatches(line).map((m) => m.group(0)!).toList();
      
      List<double> numbers = [];
      for (var m in rawMatches) {
        final cleanM = m.replaceAll(' ', '').replaceAll(',', '.');
        final n = double.tryParse(cleanM);
        // Exclude years but include large prices
        if (n != null && n > 0 && n != 2024 && n != 2025 && n != 2026) {
          numbers.add(n);
        }
      }

      // 5. Pattern Logic: Mixplus Med Table Structure
      // [Index] [Product Name Description] [Qty] [Unit] [Price] [Sum] [VAT...]
      if (numbers.isNotEmpty) {
        if (numbers.length >= 3) {
            // Usually Index is numbers[0], Qty is numbers[1], Price is numbers[2]
            foundQty = (numbers.length > 1) ? numbers[1] : numbers[0];
            foundPrice = (numbers.length > 2) ? numbers[2] : 0.0;
        } else if (numbers.length == 2) {
            foundQty = numbers[0];
            foundPrice = numbers[1];
        } else {
            foundQty = numbers[0];
            foundPrice = 0.0;
        }
      }

      // 6. DB Match (Highest priority)
      for (var product in dbProducts) {
        final pName = product['name'].toString().toLowerCase();
        if (lowerLine.contains(pName)) {
          foundProductName = product['name'];
          foundProductId = product['id'];
          foundUnit = product['unit'];
          break; 
        }
      }

      // 7. Strict Name Extraction for new items
      if (foundProductName == null && numbers.isNotEmpty && (hasUnit || numbers.length >= 2)) {
          // In this doc, name starts after index number (usually first group of digits)
          final matches = RegExp(r'^\s*\d+').allMatches(line);
          int nameStart = 0;
          if (matches.isNotEmpty) {
            nameStart = matches.first.end;
          }

          // Name ends where metadata or Qty begins (second group of digits)
          int nameEnd = line.length;
          final digitMatches = RegExp(r'\d').allMatches(line);
          for (var dm in digitMatches) {
            if (dm.start > nameStart + 5) { // Skip index number
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
