import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class PdfService {
  static Future<File> generateTransactionInvoice({
    required Map<String, dynamic> transaction,
    required String type, // 'in' or 'out'
  }) async {
    final pdf = pw.Document();
    
    // Load Fonts for Uzbek characters
    final font = await PdfGoogleFonts.robotoCondensedRegular();
    final fontBold = await PdfGoogleFonts.robotoCondensedBold();

    final isKirim = type == 'in';
    final title = isKirim ? 'KIRIM INVOYSI' : 'CHIQIM INVOYSI';
    final color = isKirim ? PdfColors.green800 : PdfColors.red800;
    
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(
      DateTime.tryParse(transaction['date_time']?.toString() ?? '') ?? DateTime.now()
    );

    // QR Data
    final qrData = "ID: ${transaction['id']}\nType: $type\nProduct: ${transaction['product_name']}\nQty: ${transaction['quantity']}\nDate: $dateStr";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
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
                      pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 18, color: color)),
                      pw.Text("№ ${transaction['id'] ?? 'N/A'}", style: pw.TextStyle(font: font, fontSize: 12)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("Sana: $dateStr", style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),

              // Transaction Details
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  children: [
                    _buildRow("Mahsulot:", transaction['product_name'] ?? 'N/A', font, fontBold),
                    _buildRow("Miqdori:", "${transaction['quantity'] ?? 0} ${transaction['unit'] ?? ''}", font, fontBold),
                    _buildRow(isKirim ? "Yetkazuvchi:" : "Qabul qiluvchi:", transaction['party'] ?? transaction['supplier_name'] ?? transaction['receiver_name'] ?? '-', font, fontBold),
                    if (transaction['price_per_unit'] != null)
                      _buildRow("Narxi (dona):", "${transaction['price_per_unit']} so'm", font, fontBold),
                    if (transaction['total_amount'] != null)
                      _buildRow("Jami summa:", "${transaction['total_amount']} so'm", font, fontBold),
                  ],
                ),
              ),
              
              pw.Spacer(),
              
              // QR and Footer
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Mas'ul shaxs: ________________", style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.SizedBox(height: 5),
                      pw.Text("Imzo: ________________", style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text("OBI Clinical Warehouse — Elektron Hujjat", style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
              ),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/invoice_${transaction['id']}.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildRow(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 11)),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11)),
        ],
      ),
    );
  }
}
