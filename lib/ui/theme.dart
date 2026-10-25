import 'package:flutter/material.dart';

import '../models/notebook.dart';

/// The look of paper, ink and leather shared by every screen.
abstract final class Pen {
  static const blue = Color(0xFF1F3A73);
  static const red = Color(0xFFC0392B);
  static const pencil = Color(0xFF6B6B6B);
  static const highlighter = Color(0x99FFEB3B);
}

abstract final class Paper {
  /// The look chosen in settings. The screen is rebuilt when these change.
  static Look look = Look.notebook;
  static PaperTone tone = PaperTone.cream;
  static bool get plain => look == Look.plain;

  static const cream = Color(0xFFFCF8EE);
  static const white = Color(0xFFFFFFFF);
  static Color get sheet => tone == PaperTone.white ? white : cream;
  static const sheetEdge = Color(0xFFEDE3CC);
  static const ruleLine = Color(0xFFB9CBE3);
  static const gridLine = Color(0xFFCAD8EA);
  static const margin = Color(0x80D9534F);
  static const cover = Color(0xFF7A5A3A);
  static const coverDark = Color(0xFF4E3824);
  static const desk = Color(0xFF2E2B28);
}

/// Colours for the buttons and text around the page: light on the dark
/// desk, dark on plain paper.
abstract final class Chrome {
  static Color get strong => Paper.plain ? const Color(0xFF2B2B2B) : Colors.white;
  static Color get normal => Paper.plain ? const Color(0xFF5F5F5F) : Colors.white70;
  static Color get quiet => Paper.plain ? const Color(0xFF8A8A8A) : Colors.white54;
  static Color get faint => Paper.plain ? const Color(0x33000000) : Colors.white24;
}

const handwriting = TextStyle(
  fontFamily: 'Kalam',
  fontSize: 19,
  height: 1.45,
  color: Pen.blue,
);

const headingHandwriting = TextStyle(
  fontFamily: 'Caveat',
  fontSize: 34,
  fontWeight: FontWeight.w700,
  height: 1.15,
  color: Pen.blue,
);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: Paper.cover,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Paper.desk,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Pen.blue,
      selectionColor: Color(0x553F72AF),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}
