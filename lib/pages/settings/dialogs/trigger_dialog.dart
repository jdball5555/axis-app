import 'package:flutter/material.dart';

void showAddTriggerDialog(
  BuildContext context,
  List<int> currentThresholds,
  Function(List<int>) onUpdate,
) {
  int currentValue = 3;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Add Trigger",
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Days Remaining:",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () => currentValue > 1
                        ? setDialogState(() => currentValue--)
                        : null,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "$currentValue",
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () => currentValue < 365
                        ? setDialogState(() => currentValue++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: Text(
                "Add",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () {
                if (!currentThresholds.contains(currentValue)) {
                  final newList = List<int>.from(currentThresholds)
                    ..add(currentValue)
                    ..sort((a, b) => b.compareTo(a));
                  onUpdate(newList);
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    ),
  );
}
