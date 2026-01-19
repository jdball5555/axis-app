import 'package:flutter/material.dart';
import '../widgets/color_wheel_picker.dart';
import '../widgets/settings_widgets.dart'; // Import the new reusable widgets

class AppearanceSettings extends StatefulWidget {
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

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  static const Color _defaultColor = Color(0xFF00C897);
  late Color _displayColor;

  @override
  void initState() {
    super.initState();
    _displayColor = widget.currentPrimaryColor;
  }

  void _handleColorChange(Color newColor) {
    setState(() {
      _displayColor = newColor;
    });
    widget.onColorChanged(newColor);
  }

  void _handleThemeChange(bool value) {
    widget.onThemeChanged(value);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Pick Accent Color",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 250,
                  width: 250,
                  child: ColorWheelPicker(
                    initialColor: _displayColor,
                    onColorChanged: _handleColorChange,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text("Reset"),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      onPressed: () {
                        _handleColorChange(_defaultColor);
                        Navigator.pop(ctx);
                      },
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _displayColor,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Done"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = !widget.isLightMode;

    return ResponsiveSettingsGrid(
      children: [
        // --- TILE 1: DARK MODE ---
        GradientSettingsTile(
          icon: isDark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
          title: "Dark Mode",
          subtitle: isDark ? "On" : "Off",
          trailing: Switch(
            value: isDark,
            activeColor: _displayColor,
            onChanged: (val) => _handleThemeChange(!val),
          ),
          onTap: () => _handleThemeChange(!isDark),
        ),

        // --- TILE 2: ACCENT COLOR ---
        GradientSettingsTile(
          icon: Icons.palette_outlined,
          title: "Accent Color",
          subtitle: "Tap to change",
          trailing: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _displayColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
              ],
            ),
          ),
          onTap: () => _showColorPicker(context),
        ),
      ],
    );
  }
}
