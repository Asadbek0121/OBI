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
