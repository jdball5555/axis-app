import 'package:flutter/material.dart';
import '../widgets/settings_widgets.dart';
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

  void _showResetConfirmation(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            const Text("Clear Current Inventory"),
          ],
        ),
        content: Text(
          "Are you sure you want to delete all data from this inventory? "
          "This action cannot be undone.",
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              onResetData(); // Trigger actual reset
            },
            child: Text(
              "Clear Data",
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientSettingsTile(
          icon: Icons.download,
          title: "Upload Inventory",
          subtitle: "Import your items from CSV",
          onTap: onImportInventory,
        ),
        GradientSettingsTile(
          icon: Icons.history,
          title: "Upload Activity Log",
          subtitle: "Import usage history from CSV",
          onTap: onImportActivity,
        ),
        GradientSettingsTile(
          icon: Icons.info_outline,
          title: "View CSV Formats",
          subtitle: "See required column layouts",
          onTap: () => showCSVFormatsDialog(context),
        ),
        // Removed the SizedBox here to eliminate the gap
        GradientSettingsTile(
          icon: Icons.delete_sweep,
          title: "Clear Current Inventory",
          subtitle: "Remove items & history from this list only",
          onTap: () => _showResetConfirmation(context),
        ),
      ],
    );
  }
}
