import 'package:flutter/material.dart';
import '../widgets/settings_format.dart';

class InfoSettings extends StatelessWidget {
  final String appVersion;

  const InfoSettings({super.key, required this.appVersion});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsHeader(title: "INFO"),
        ResponsiveSettingsGrid(
          children: [
            GradientSettingsTile(
              icon: Icons.developer_mode,
              title: "App Version",
              subtitle: "v$appVersion",
              trailing: const SizedBox.shrink(), // This hides the arrow
            ),
          ],
        ),
      ],
    );
  }
}
