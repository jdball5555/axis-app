import 'package:flutter/material.dart';

void showCSVFormatsDialog(BuildContext context) {
  final theme = Theme.of(context);
  DataColumn buildCol(String label) => DataColumn(
    label: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    ),
  );
  DataRow buildRow(List<String> cells) => DataRow(
    cells: cells
        .map(
          (c) => DataCell(
            Text(c, style: TextStyle(color: theme.colorScheme.onSurface)),
          ),
        )
        .toList(),
  );

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "CSV Data Viewer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Inventory Format",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        columns: [
                          buildCol("Name"),
                          buildCol("Type"),
                          buildCol("Room Location"),
                          buildCol("Quantity"),
                        ],
                        rows: [
                          buildRow([
                            "Coffee Beans",
                            "Consumable",
                            "Pantry",
                            "500",
                          ]),
                          buildRow(["Milk", "Consumable", "Fridge", "1.5"]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Activity Log Format",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        columns: [
                          buildCol("Timestamp"),
                          buildCol("Action"),
                          buildCol("Item Name"),
                          buildCol("Room"),
                          buildCol("Change"),
                          buildCol("Total"),
                        ],
                        rows: [
                          buildRow([
                            "2025-01-01",
                            "REMOVE",
                            "Milk",
                            "Kitchen",
                            "-0.2",
                            "1.3",
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.dividerColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  "Close",
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
