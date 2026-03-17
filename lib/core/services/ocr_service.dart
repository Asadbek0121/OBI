import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:clinical_warehouse/app_config.dart';
import 'package:flutter/foundation.dart';

class OCRService {
  // We'll use raw HTTP to have full control over the API version (v1)
  // This avoids 'model not found' errors common in some library versions
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  Future<Map<String, dynamic>?> processDocument(File file) async {
    try {
      final apiKey = AppConfig.geminiApiKey;
      if (apiKey.isEmpty) {
        throw Exception("Gemini API Key is missing in AppConfig.");
      }

      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": """
                    You are a professional accounting assistant. 
                    Observe the attached image/document and extract the items list into a JSON format.
                    The document is a 'Shet na oplatu', 'Nakladnaya', or 'Invoice'.
                    
                    Return ONLY this JSON:
                    {
                      "metadata": { "date": "YYYY-MM-DD", "supplier": "Name", "doc_no": "Number" },
                      "items": [
                        { "name": "Item Name", "unit": "шт/уп", "quantity": 0.0, "price": 0.0, "tax_percent": 0.0 }
                      ]
                    }
                    
                    Rules:
                    1. Focus on the main items table.
                    2. If the language is Russian or Uzbek, map the column names to the JSON keys correctly.
                    3. Return ONLY the JSON block, no markdown or text.
                  """
                },
                {
                  "inline_data": {
                    "mime_type": _getMimeType(file.path),
                    "data": base64Image
                  }
                }
              ]
            }
          ],
          "generationConfig": {
            "temperature": 0.1,
            "topP": 0.95,
            "topK": 64,
            "maxOutputTokens": 8192
          }
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final String? textResponse = 
            decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];
        
        if (textResponse != null) {
          debugPrint("🤖 Gemini Raw Response: $textResponse");
          
          // Robust JSON extraction
          final jsonRegex = RegExp(r'\{[\s\S]*\}');
          final match = jsonRegex.firstMatch(textResponse);
          
          if (match != null) {
            final jsonStr = match.group(0)!;
            return jsonDecode(jsonStr);
          }
        }
      } else {
        debugPrint("❌ OCR API Error (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint("OCR Critical Error: $e");
    }
    return null;
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      default: return 'image/jpeg';
    }
  }
}
