import 'package:flutter/material.dart';
import '../widgets/settings_section.dart';
import '../dialogs/about_dialog.dart';

class InfoSettings extends StatelessWidget {
  final String appVersion;

  const InfoSettings({super.key, required this.appVersion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "INFO",
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
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text("About Axis"),
              onTap: () => showAxisAboutDialog(context, appVersion),
            ),
            ListTile(
              leading: const Icon(Icons.developer_mode),
              title: const Text("Version"),
              trailing: Text(
                "v$appVersion",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
