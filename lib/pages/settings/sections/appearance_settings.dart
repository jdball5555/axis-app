import 'package:flutter/material.dart';
import '../widgets/settings_format.dart';

class AppearanceSettings extends StatelessWidget {
  final bool isLightMode;
  final Function(bool) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  const AppearanceSettings({
    super.key,
    required this.isLightMode,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onColorChanged,
  });

  void _handleThemeChange(BuildContext context, bool value) {
    onThemeChanged(value);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // A quick helper to draw the 3 theme color circles
  Widget _buildColorCircle(Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = !isLightMode;

    return ResponsiveSettingsGrid(
      children: [
        // --- TILE 1: DARK MODE ---
        GradientSettingsTile(
          icon: isDark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
          title: "Dark Mode",
          subtitle: isDark ? "On" : "Off",
          trailing: Switch(
            value: isDark,
            activeColor: currentPrimaryColor,
            onChanged: (val) => _handleThemeChange(context, !val),
          ),
        ),

        // --- TILE 2: APP THEME (STATIC) ---
        GradientSettingsTile(
          icon: Icons.palette_outlined,
          title: "App Theme",
          subtitle: "Axis Default Palette",
          // By leaving out the onTap parameter, the tile becomes completely static (No arrow, no clicks)
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildColorCircle(const Color(0xFF00C897)), // Teal
              const SizedBox(width: 4),
              _buildColorCircle(Colors.orangeAccent), // Orange
              const SizedBox(width: 4),
              _buildColorCircle(Colors.redAccent), // Red
            ],
          ),
        ),
      ],
    );
  }
}
