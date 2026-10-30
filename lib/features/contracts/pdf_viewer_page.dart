import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../core/widgets/glass_ui.dart';
import '../../core/theme/app_colors.dart';
import 'package:printing/printing.dart';

class PdfViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const PdfViewerPage({super.key, required this.file, required this.title});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late PdfControllerPinch _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.file.path),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 1. PDF Viewer (Fills the screen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 60, 12, 12),
              child: GlassCard(
                padding: EdgeInsets.zero,
                radius: 16,
                child: PdfViewPinch(
                  controller: _pdfController,
                ),
              ),
            ),

            // 2. Floating Header Overlay
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                radius: 12,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildActionButton(
                      icon: Icons.print_rounded,
                      onTap: () async {
                        await Printing.layoutPdf(
                          onLayout: (format) => widget.file.readAsBytes(),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildActionButton(
                      icon: Icons.share_rounded,
                      onTap: () async {
                        await Printing.sharePdf(
                          bytes: await widget.file.readAsBytes(),
                          filename: widget.title,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      ),
    );
  }
}
