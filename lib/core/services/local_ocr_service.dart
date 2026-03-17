import 'dart:io';
import 'package:flutter/services.dart';
import 'package:clinical_warehouse/core/services/local_ai_parser.dart';
import 'package:flutter/foundation.dart';

class LocalOCRService {
  static const MethodChannel _channel = MethodChannel('uz.asadbek.obi/ocr');

  Future<List<Map<String, dynamic>>?> processImageLocally(File file) async {
    try {
      // 1. Call Native MacOS OCR via Platform Channel
      final String? rawText = await _channel.invokeMethod('performOCR', {
        "path": file.path,
      });

      if (rawText == null || rawText.isEmpty) {
        debugPrint("📸 Local OCR: No text found.");
        return null;
      }

      debugPrint("📸 Local OCR Raw Text: $rawText");

      // 2. Use our Database-driven Parser to structure the text
      // This is the "Ajoyib" part - it matches recognized text with your DB products
      final structuredData = await LocalAIParser.parseUsingDatabase(rawText);
      
      return structuredData;
    } catch (e) {
      debugPrint("❌ Local OCR Error: $e");
      return null;
    }
  }
}
