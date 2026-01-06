import 'package:flutter/material.dart';
import '../widgets/settings_section.dart';
import '../dialogs/csv_formats_dialog.dart';

class DataSettings extends StatelessWidget {
  final VoidCallback onImportInventory;
  final VoidCallback onImportActivity;
  final VoidCallback onResetData;

  const DataSettings({
    super.key,
    required this.onImportInventory,
    required this.onImportActivity,
    required this.onResetData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "DATA",
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
              leading: const Icon(Icons.download),
              title: const Text("Upload Inventory"),
              onTap: onImportInventory,
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("Upload Activity Log"),
              onTap: onImportActivity,
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Reset Data",
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: onResetData,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("View CSV Formats"),
              onTap: () => showCSVFormatsDialog(context),
            ),
          ],
        ),
      ],
    );
  }
}
