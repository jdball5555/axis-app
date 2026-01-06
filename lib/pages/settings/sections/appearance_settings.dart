import 'package:flutter/material.dart';
import '../widgets/settings_section.dart';
import '../widgets/color_wheel_picker.dart';

class AppearanceSettings extends StatelessWidget {
  final bool isLightMode;
  final Function(bool) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onColorChanged;

  static const Color _defaultColor = Color(0xFF00C897);

  const AppearanceSettings({
    super.key,
    required this.isLightMode,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onColorChanged,
  });

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          // Wrapped in ScrollView to prevent cut-off in landscape
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
                // Fixed Size for the Wheel
                SizedBox(
                  height: 250,
                  width: 250,
                  child: ColorWheelPicker(
                    initialColor: currentPrimaryColor,
                    onColorChanged: onColorChanged,
                  ),
                ),
                const SizedBox(height: 20),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text("Reset"),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      onPressed: () {
                        onColorChanged(_defaultColor);
                        Navigator.pop(ctx);
                      },
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "APPEARANCE",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        SettingsSection(
          children: [
            SwitchListTile(
              title: Text(
                "Dark Mode",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              secondary: Icon(
                !isLightMode ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                color: theme.iconTheme.color,
              ),
              value: !isLightMode,
              activeColor: theme.colorScheme.primary,
              onChanged: (val) => onThemeChanged(!val),
            ),
            Divider(color: theme.dividerColor, height: 1),
            ListTile(
              title: Text(
                "Accent Color",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: GestureDetector(
                onTap: () => _showColorPicker(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: currentPrimaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
