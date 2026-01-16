import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode_widget/barcode_widget.dart' as bc;

class PrintService {
  static Future<void> printAssetPassport(Map<String, dynamic> asset) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text("JIHOZ PASPORTI", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 20),
              _item("Nomi:", asset['name']),
              _item("Model/Marka:", asset['model'] ?? '-'),
              _item("Seriya raqami:", asset['serial_number'] ?? '-'),
              _item("Kategoriya:", asset['category_name'] ?? '-'),
              _item("Holati:", asset['status'] ?? '-'),
              _item("Rangi:", asset['color'] ?? '-'),
              pw.Divider(),
              _item("Joylashuv:", "${asset['parent_location_name'] ?? ''} > ${asset['location_name'] ?? ''}"),
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
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text("Shtrix kod: ${asset['barcode'] ?? '-'}", style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.bottomRight,
                child: pw.Text("Sana: ${DateTime.now().toString().substring(0, 16)}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
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
  }

  static Future<void> printAssetBarcode(Map<String, dynamic> asset) async {
    final pdf = pw.Document();

    // 50mm x 30mm Label Size (Common for stickers)
    final format = PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(2),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  asset['name'].toString().length > 20 
                    ? asset['name'].toString().substring(0, 20) 
                    : asset['name'],
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  maxLines: 1,
                ),
                pw.SizedBox(height: 2),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: asset['barcode'] ?? 'N/A',
                  width: 130,
                  height: 40,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 6),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Sticker_${asset['barcode']}.pdf',
    );
  }

  static Future<void> printOrderQR(String qrData, String label) async {
    final pdf = pw.Document();

    // 80mm Roll Width
    final format = PdfPageFormat.roll80;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text("YUK QABUL QILISH", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: 150,
                height: 150,
              ),
              pw.SizedBox(height: 10),
              pw.Text(label, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Text("Kamerada skanerlang", style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(),
              pw.Text("Clinical Warehouse System", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'OrderQR_$label.pdf',
    );
  }

  static pw.Widget _item(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(width: 10),
          pw.Text(value, style: const pw.TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
