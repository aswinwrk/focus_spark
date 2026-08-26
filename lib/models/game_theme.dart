import 'package:flutter/material.dart';

class GameTheme {
  final String name;
  final List<Color> bgGradient;
  final Color panelBg;
  final Color panelBorder;
  final Color tileActiveGlow;
  final Color tileDefault;
  final Color textPrimary;
  final Color accentColor;
  final Color successColor;

  const GameTheme({
    required this.name,
    required this.bgGradient,
    required this.panelBg,
    required this.panelBorder,
    required this.tileActiveGlow,
    required this.tileDefault,
    required this.textPrimary,
    required this.accentColor,
    required this.successColor,
  });
}

const List<GameTheme> gameThemes = [
  GameTheme(
    name: 'Cosmic Indigo',
    bgGradient: [Color(0xFF0C0A1A), Color(0xFF181135), Color(0xFF06050D)],
    panelBg: Color(0x1F221B35),
    panelBorder: Color(0x388B5CF6),
    tileActiveGlow: Color(0xFFC084FC),
    tileDefault: Color(0x14FFFFFF),
    textPrimary: Colors.white,
    accentColor: Color(0xFFA78BFA),
    successColor: Color(0xFF10B981),
  ),
  GameTheme(
    name: 'Sage Calm',
    bgGradient: [Color(0xFF161E1A), Color(0xFF243329), Color(0xFF0F1411)],
    panelBg: Color(0x1F2A382F),
    panelBorder: Color(0x3B86EFAC),
    tileActiveGlow: Color(0xFF4ADE80),
    tileDefault: Color(0x10FFFFFF),
    textPrimary: Color(0xFFF1FDF7),
    accentColor: Color(0xFF86EFAC),
    successColor: Color(0xFF34D399),
  ),
  GameTheme(
    name: 'Midnight Cyber',
    bgGradient: [Color(0xFF030006), Color(0xFF070B18), Color(0xFF010003)],
    panelBg: Color(0x240A1021),
    panelBorder: Color(0x4706B6D4),
    tileActiveGlow: Color(0xFF22D3EE),
    tileDefault: Color(0x16FFFFFF),
    textPrimary: Color(0xFFF8FAFC),
    accentColor: Color(0xFF06B6D4),
    successColor: Color(0xFF06B6D4),
  ),
];
