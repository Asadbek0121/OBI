import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:clinical_warehouse/app_config.dart';
import 'package:flutter/foundation.dart';

class OCRService {
  // Use a fallback or AppConfig.geminiApiKey
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  Future<Map<String, dynamic>?> processDocument(File file) async {
    try {
      final apiKey = AppConfig.geminiApiKey.isEmpty ? _apiKey : AppConfig.geminiApiKey;
      if (apiKey.isEmpty) {
        throw Exception("Gemini API Key is not configured.");
      }

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
      );

      final bytes = await file.readAsBytes();
      final extension = file.path.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (extension == 'pdf') mimeType = 'application/pdf';
      if (extension == 'png') mimeType = 'image/png';

      final content = [
        Content.multi([
          DataPart(mimeType, bytes), 
          TextPart("""
            You are an expert accounting document parser. 
            Analyze the provided image/PDF which is a 'Счет на оплату', 'Спецификация', 'Invoice' or 'Nakladnoy' for a medical/laboratory warehouse.
            
            EXTRACT DATA INTO THIS JSON FORMAT:
            {
              "metadata": {
                "date": "YYYY-MM-DD",
                "supplier": "Full name of the Поставщик/Supplier",
                "document_number": "Number from the title"
              },
              "items": [
                {
                  "name": "Mahsulot nomi (Product name from the table)",
                  "unit": "Birlik (e.g. шт, уп, флак, мл)",
                  "quantity": 0.0,
                  "price": 0.0,
                  "tax_percent": 0.0,
                  "tax_sum": 0.0,
                  "total": 0.0
                }
              ]
            }

            CRITICAL RULES:
            1. Look for a central table. The columns are usually: №, Наименование товара, Ед. изм., Кол-во, Цена, НДС, Сумма.
            2. If 'НДС' (Tax) is included in the price, calculate the tax_sum accordingly.
            3. Clean the product names from technical symbols if possible.
            4. If the field is missing, return null or 0.0.
            5. RETURN ONLY THE JSON BLOCK.
          """),
        ]),
      ];

      final response = await model.generateContent(content);
      final rawText = response.text;
      debugPrint("🤖 Gemini Raw Response: $rawText");

      if (rawText != null) {
        // Use regex to find the first JSON-like block to be more robust
        final jsonRegex = RegExp(r'\{[\s\S]*\}');
        final match = jsonRegex.firstMatch(rawText);
        
        if (match != null) {
          final jsonStr = match.group(0)!;
          return jsonDecode(jsonStr);
        }
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
    }
    return null;
  }
}
