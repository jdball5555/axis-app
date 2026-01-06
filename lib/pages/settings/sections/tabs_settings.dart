import 'package:flutter/material.dart';
import '../../../models/tab_data.dart';

class TabsSettings extends StatelessWidget {
  final List<TabData> orderedTabs;
  final Set<String> activeTabIds;
  final Function(int, int) onReorder;
  final Function(String, bool) onToggle;

  const TabsSettings({
    super.key,
    required this.orderedTabs,
    required this.activeTabIds,
    required this.onReorder,
    required this.onToggle,
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
            "TABS (Drag to Reorder)",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: onReorder,
            children: orderedTabs
                .map(
                  (tab) => ListTile(
                    key: ValueKey(tab.id),
                    leading: Icon(tab.icon),
                    title: Text(
                      tab.id.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: activeTabIds.contains(tab.id),
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) => onToggle(tab.id, val),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.drag_handle, color: theme.dividerColor),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
