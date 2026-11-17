import 'package:flutter/material.dart';

/// Palette de la partie « agent » : bleu marine façon GPS, accents bleu
/// électrique / cyan (les mêmes que ceux du plan), et trois couleurs de statut.
class AgentColors {
  static const navy = Color(0xFF0B1B3A);
  static const navyLight = Color(0xFF17315F);
  static const blue = Color(0xFF1E6FE8);
  static const cyan = Color(0xFF33CCFF);

  static const bg = Color(0xFFF2F5FA);
  static const card = Colors.white;
  static const line = Color(0xFFE3E8F1);
  static const ink = Color(0xFF1B2437);
  static const muted = Color(0xFF6B7690);

  static const ok = Color(0xFF22B45A);
  static const warn = Color(0xFFFFA800);
  static const bad = Color(0xFFFF4D57);
}

ThemeData buildAgentTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AgentColors.blue,
    brightness: Brightness.light,
  ).copyWith(primary: AgentColors.blue, surface: AgentColors.card);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AgentColors.bg,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AgentColors.navy,
      indicatorColor: AgentColors.blue,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : const Color(0xFF9FB0D0),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? Colors.white : const Color(0xFF9FB0D0),
        );
      }),
    ),
  );
}
