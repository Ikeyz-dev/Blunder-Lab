import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF262421);
  static const card = Color(0xFF302E2B);
  static const cardLight = Color(0xFF3A3835);
  static const green = Color(0xFF81B64C);
  static const red = Color(0xFFCA3431);
  static const orange = Color(0xFFE58F2A);
  static const yellow = Color(0xFFF7C631);
  static const blue = Color(0xFF4A90D9);
  static const muted = Color(0xFF9B9895);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: Brightness.dark,
  ).copyWith(primary: AppColors.green, onPrimary: Colors.black);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

BoxDecoration cardDecoration({Color? color, Color? border}) {
  return BoxDecoration(
    color: color ?? AppColors.card,
    borderRadius: BorderRadius.circular(14),
    border: border == null ? null : Border.all(color: border, width: 1.5),
  );
}
