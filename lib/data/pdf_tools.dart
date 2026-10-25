import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/notebook.dart';

/// A PDF with one picture per page, each the shape of a notebook page.
Future<Uint8List> picturesToPdf(List<Uint8List> pngs) async {
  final doc = pw.Document(title: 'Notebook pages');
  for (final png in pngs) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}

/// Each page of a PDF as a PNG picture, ready to write on.
Future<List<Uint8List>> pdfToPictures(Uint8List pdf) async => [
  await for (final page in Printing.raster(pdf, dpi: 150)) await page.toPng(),
];
