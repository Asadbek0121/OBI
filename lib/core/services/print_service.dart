import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


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

    // 40mm x 30mm Label Size
    final format = PdfPageFormat(40 * PdfPageFormat.mm, 30 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(1), // Minimal margin
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                  child: pw.Text(
                    asset['name'].toString(),
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
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
                  textStyle: const pw.TextStyle(fontSize: 6),
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
  }

  static Future<void> printOrderQR(String qrData, String label) async {
    final pdf = pw.Document();

    // 40mm x 30mm Label Size (Standard Xprinter Label)
    final format = PdfPageFormat(40 * PdfPageFormat.mm, 30 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(1),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text("QABUL: $label", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
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
  }

  static Future<void> printImage(Uint8List imageBytes, String label) async {
    final pdf = pw.Document();
    
    // Use A4 or Standard Roll width based on need. 
    // Since user asked for printing the order photo, usually A4 or Standard is better than 40x30 Label.
    // Let's offer standard A4 for easy viewing or Roll 80.
    // However, if they want it on sticker machine... it will be tiny.
    // Let's assume standard printer for "Photo Order" as it contains details.
    
    final image = pw.MemoryImage(imageBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
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
  }

  static Future<void> printWaybill(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
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
                      pw.Text("OMBOR YO'LLANMASI (Nakladnoy)", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 5),
                      pw.Text("No: #ORD-${order['id']}", style: pw.TextStyle(fontSize: 14)),
                      pw.Text("Sana: ${order['created_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? DateTime.now().toString().substring(0,16)}", style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ]
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blue, width: 2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Text("KASALXONA OMBORXONASI\nQABUL QILISH AKTI", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
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
                        pw.Text("Yuboruvchi (Ombor):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text("Markaziy Ombor", style: const pw.TextStyle(fontSize: 14)),
                        pw.Text("Qabul Qiluvchi (Filial/Bo'lim):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text("${order['branch_name'] ?? 'Filial'}", style: const pw.TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Items Table
              pw.Text("Tarkibi:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 1),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
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
                      pw.Text("Topshirdi (Omborchi):", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 30),
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("(F.I.SH / Imzo)", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text("Qabul qildi:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 30),
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text("(F.I.SH / Imzo)", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                    ]
                  ),
                ]
              ),

              pw.Spacer(),
              pw.Center(child: pw.Text("Tizim orqali avtomatik ravishda tayyorlangan.", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Waybill_ORD${order['id']}.pdf',
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
