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
            You are a professional accounting document parser for a laboratory warehouse.
            Parse the provided document (Invoice, Sчет на оплату, Nakladnoy, etc.) and extract the data into the following JSON format:

            {
              "metadata": {
                "date": "YYYY-MM-DD",
                "supplier": "Name of supplier",
                "document_number": "Number"
              },
              "items": [
                {
                  "name": "Product name",
                  "unit": "Unit (e.g. шт, уп, мл)",
                  "quantity": 0.0,
                  "price": 0.0,
                  "tax_percent": 0.0,
                  "tax_sum": 0.0,
                  "total": 0.0
                }
              ]
            }

            Rules:
            1. If date is not found, use current date.
            2. Be precise with numbers. 
            3. Return ONLY JSON, no markdown formatting.
            4. If the document is in Russian or Uzbek, map fields correctly.
          """),
        ]),
      ];

      final response = await model.generateContent(content);
      final jsonStr = response.text?.replaceAll('```json', '').replaceAll('```', '').trim();
      
      if (jsonStr != null) {
        return jsonDecode(jsonStr);
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
    }
    return null;
  }
}
