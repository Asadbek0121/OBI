import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


class PrintService {
  /// Internal helper to load Unicode fonts (Roboto) with error handling.
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? fontBase;
    pw.Font? fontBold;
    try {
      fontBase = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (e) {
      debugPrint("⚠️ PrintService: Google Fonts loading failed, using fallback: $e");
    }
    return {'base': fontBase, 'bold': fontBold};
  }

  static Future<void> printAssetPassport(Map<String, dynamic> asset) async {
    try {
      final pdf = pw.Document();
      final fonts = await _loadFonts();
      final fontBase = fonts['base'];
      final fontBold = fonts['bold'];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          theme: pw.ThemeData.withFont(
            base: fontBase ?? pw.Font.helvetica(), 
            bold: fontBold ?? pw.Font.helveticaBold()
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text("JIHOZ PASPORTI", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: fontBold)),
                ),
                pw.SizedBox(height: 20),
                _item("Nomi:", asset['name'], fontBase, fontBold),
                _item("Model/Marka:", asset['model'] ?? '-', fontBase, fontBold),
                _item("Seriya raqami:", asset['serial_number'] ?? '-', fontBase, fontBold),
                _item("Kategoriya:", asset['category_name'] ?? '-', fontBase, fontBold),
                _item("Holati:", asset['status'] ?? '-', fontBase, fontBold),
                _item("Rangi:", asset['color'] ?? '-', fontBase, fontBold),
                pw.Divider(),
                _item("Joylashuv:", "${asset['parent_location_name'] ?? ''} > ${asset['location_name'] ?? ''}", fontBase, fontBold),
                pw.SizedBox(height: 40),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: asset['barcode'] ?? 'N/A',
                        width: 250,
                        height: 80,
                        drawText: true,
                        textStyle: pw.TextStyle(font: fontBase, fontSize: 10),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text("Shtrix kod: ${asset['barcode'] ?? '-'}", style: pw.TextStyle(fontSize: 10, font: fontBase)),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Align(
                  alignment: pw.Alignment.bottomRight,
                  child: pw.Text("Sana: ${DateTime.now().toString().substring(0, 16)}", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey, font: fontBase)),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Passport_${asset['barcode'] ?? 'asset'}.pdf',
      );
    } catch (e) {
      debugPrint("❌ PrintService (AssetPassport) Error: $e");
      rethrow;
    }
  }

  static Future<void> printAssetBarcode(Map<String, dynamic> asset) async {
    try {
      final pdf = pw.Document();
      final fonts = await _loadFonts();
      final fontBase = fonts['base'];
      final fontBold = fonts['bold'];

      // 40mm x 30mm Label Size
      final format = PdfPageFormat(40 * PdfPageFormat.mm, 30 * PdfPageFormat.mm);

      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(1), // Minimal margin
          theme: pw.ThemeData.withFont(
            base: fontBase ?? pw.Font.helvetica(), 
            bold: fontBold ?? pw.Font.helveticaBold()
          ),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                    child: pw.Text(
                      asset['name'].toString(),
                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, font: fontBold),
                      maxLines: 2,
                      textAlign: pw.TextAlign.center,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: asset['barcode'] ?? 'N/A',
                    width: 36 * PdfPageFormat.mm, // Fit within width
                    height: 12 * PdfPageFormat.mm, // Reduced height to fit text
                    drawText: true,
                    textStyle: pw.TextStyle(fontSize: 6, font: fontBase),
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat f) async => pdf.save(),
        name: 'Sticker_${asset['barcode']}.pdf',
        format: format, // Hint for the print dialog
      );
    } catch (e) {
      debugPrint("❌ PrintService (AssetBarcode) Error: $e");
      rethrow;
    }
  }

  static Future<void> printOrderQR(String qrData, String label) async {
    try {
      final pdf = pw.Document();
      final fonts = await _loadFonts();
      final fontBase = fonts['base'];
      final fontBold = fonts['bold'];

      // 40mm x 30mm Label Size (Standard Xprinter Label)
      final format = PdfPageFormat(40 * PdfPageFormat.mm, 30 * PdfPageFormat.mm);

      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(1),
          theme: pw.ThemeData.withFont(
            base: fontBase ?? pw.Font.helvetica(), 
            bold: fontBold ?? pw.Font.helveticaBold()
          ),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text("QABUL: $label", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: fontBold)),
                  pw.SizedBox(height: 1),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrData,
                    width: 22 * PdfPageFormat.mm,
                    height: 22 * PdfPageFormat.mm,
                    drawText: false,
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat f) async => pdf.save(),
        name: 'OrderQR_$label.pdf',
        format: format, // Hint for the print dialog
      );
    } catch (e) {
      debugPrint("❌ PrintService (OrderQR) Error: $e");
      rethrow;
    }
  }

  static Future<void> printImage(Uint8List imageBytes, String label) async {
    try {
      final pdf = pw.Document();
      final fonts = await _loadFonts();
      final fontBase = fonts['base'];
      final fontBold = fonts['bold'];
      
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(
            base: fontBase ?? pw.Font.helvetica(), 
            bold: fontBold ?? pw.Font.helveticaBold()
          ),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'OrderPhoto_$label.pdf',
      );
    } catch (e) {
      debugPrint("❌ PrintService (Image) Error: $e");
      rethrow;
    }
  }

  static Future<void> printWaybill(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    try {
      final pdf = pw.Document();
      final fonts = await _loadFonts();
      final fontBase = fonts['base'];
      final fontBold = fonts['bold'];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          theme: pw.ThemeData.withFont(
            base: fontBase ?? pw.Font.helvetica(), 
            bold: fontBold ?? pw.Font.helveticaBold()
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("OMBOR YO'LLANMASI (Nakladnoy)", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: fontBold)),
                      pw.SizedBox(height: 5),
                      pw.Text("No: #ORD-${order['id']}", style: pw.TextStyle(fontSize: 14, font: fontBase)),
                      pw.Text("Sana: ${order['created_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? DateTime.now().toString().substring(0,16)}", style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700, font: fontBase)),
                    ]
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blue, width: 2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Text("KASALXONA OMBORXONASI\nQABUL QILISH AKTI", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue, font: fontBold)),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              // Parties Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Yuboruvchi (Ombor):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, font: fontBold)),
                        pw.Text("Markaziy Ombor", style: pw.TextStyle(fontSize: 14, font: fontBase)),
                        pw.Text("Qabul Qiluvchi (Filial/Bo'lim):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, font: fontBold)),
                        pw.Text("${order['branch_name'] ?? 'Filial'}", style: pw.TextStyle(fontSize: 14, font: fontBase)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Items Table
              pw.Text("Tarkibi:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, font: fontBold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 1),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, font: fontBold),
                cellStyle: pw.TextStyle(font: fontBase),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
                headers: ['#', 'Mahsulot nomi', 'Miqdori', 'O\'lchov birligi'],
                data: List<List<String>>.generate(items.length, (index) {
                  final item = items[index];
                  return [
                    (index + 1).toString(),
                    item['product_name'].toString(),
                    item['quantity'].toString(),
                    item['unit'].toString(),
                  ];
                }),
              ),
              pw.SizedBox(height: 40),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text("Topshirdi (Omborchi):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold)),
                      pw.SizedBox(height: 30),
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("(F.I.SH / Imzo)", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: fontBase)),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text("Qabul qildi:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold)),
                      pw.SizedBox(height: 30),
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("(F.I.SH / Imzo)", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: fontBase)),
                    ]
                  ),
                ]
              ),

              pw.Spacer(),
              pw.Center(child: pw.Text("Tizim orqali avtomatik ravishda tayyorlangan.", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey, font: fontBase))),
            ],
          );
        },
      ),
    );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Waybill_ORD${order['id']}.pdf',
      );
    } catch (e) {
      debugPrint("❌ PrintService (Waybill) Error: $e");
      rethrow;
    }
  }

  static pw.Widget _item(String label, String value, pw.Font? fontBase, pw.Font? fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, font: fontBold)),
          pw.SizedBox(width: 10),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, font: fontBase)),
        ],
      ),
    );
  }
}
