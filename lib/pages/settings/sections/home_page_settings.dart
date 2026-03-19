import 'package:flutter/material.dart';
import '../widgets/settings_format.dart';
import 'edit_hp_settings.dart';

class InventoryConfig {
  final String id;
  final String name;
  final List<String> rooms;
  InventoryConfig({required this.id, required this.name, required this.rooms});
}

class HomePageSettings extends StatefulWidget {
  final List<InventoryConfig> inventories;
  final Map<String, Set<String>> runoutMutedMap;
  final Map<String, Set<String>> usageMutedMap;
  final Function(int, int) onReorderInventories;
  final Function(String, String, bool) onToggleRunoutMute;
  final Function(String, String, bool) onToggleUsageMute;

  const HomePageSettings({
    super.key,
    required this.inventories,
    required this.runoutMutedMap,
    required this.usageMutedMap,
    required this.onReorderInventories,
    required this.onToggleRunoutMute,
    required this.onToggleUsageMute,
  });

  @override
  State<HomePageSettings> createState() => _HomePageSettingsState();
}

class _HomePageSettingsState extends State<HomePageSettings> {
  late List<InventoryConfig> _localInventories;
  late Map<String, Set<String>> _localRunoutMuted;
  late Map<String, Set<String>> _localUsageMuted;

  @override
  void initState() {
    super.initState();
    _localInventories = List.from(widget.inventories);
    _localRunoutMuted = {
      for (var k in widget.runoutMutedMap.keys)
        k: Set.from(widget.runoutMutedMap[k]!),
    };
    _localUsageMuted = {
      for (var k in widget.usageMutedMap.keys)
        k: Set.from(widget.usageMutedMap[k]!),
    };
  }

  void _openLayoutEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditHPSettings(
          onSave: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Home layout updated.")),
              );
            }
          },
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
        const SettingsHeader(title: "Home Layout"),
        ResponsiveSettingsGrid(
          children: [
            GradientSettingsTile(
              icon: Icons.dashboard_customize,
              title: "Customize Layout",
              subtitle: "Drag to Reorder • Pinch to Resize",
              onTap: _openLayoutEditor,
            ),
          ],
        ),

        const SizedBox(height: 15),
        const SettingsHeader(title: "Alerts by Inventory"),

        if (_localInventories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No inventories found."),
          ),

        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) =>
              Material(color: Colors.transparent, child: child),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _localInventories.removeAt(oldIndex);
              _localInventories.insert(newIndex, item);
            });
            widget.onReorderInventories(oldIndex, newIndex);
          },
          children: _localInventories
              .asMap()
              .entries
              .map(
                (entry) => _buildInventoryCard(theme, entry.value, entry.key),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildInventoryCard(
    ThemeData theme,
    InventoryConfig inventory,
    int index,
  ) {
    final int totalRooms = inventory.rooms.length;
    final Set<String> runoutMuted = _localRunoutMuted[inventory.id] ?? {};
    final Set<String> usageMuted = _localUsageMuted[inventory.id] ?? {};

    final int activeRunout =
        totalRooms - runoutMuted.intersection(inventory.rooms.toSet()).length;
    final int activeUsage =
        totalRooms - usageMuted.intersection(inventory.rooms.toSet()).length;

    return Container(
      key: ValueKey("inv_${inventory.id}"),
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.1),
            theme.colorScheme.primary.withOpacity(0.4),
          ],
        ),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: ExpansionTile(
        key: PageStorageKey("exp_${inventory.id}"),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          inventory.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          "Restock: $activeRunout/$totalRooms • Usage: $activeUsage/$totalRooms",
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: Colors.black),
        ),
        children: [
          _buildAlertSection(
            theme: theme,
            title: "Restock Alerts",
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.redAccent,
            rooms: inventory.rooms,
            mutedSet: runoutMuted,
            onToggle: (room, isMuted) {
              setState(() {
                if (isMuted)
                  _localRunoutMuted[inventory.id]?.add(room);
                else
                  _localRunoutMuted[inventory.id]?.remove(room);
              });
              widget.onToggleRunoutMute(inventory.id, room, isMuted);
            },
          ),
          _buildAlertSection(
            theme: theme,
            title: "Usage Checks",
            icon: Icons.history_edu,
            iconColor: theme.colorScheme.primary,
            rooms: inventory.rooms,
            mutedSet: usageMuted,
            onToggle: (room, isMuted) {
              setState(() {
                if (isMuted)
                  _localUsageMuted[inventory.id]?.add(room);
                else
                  _localUsageMuted[inventory.id]?.remove(room);
              });
              widget.onToggleUsageMute(inventory.id, room, isMuted);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSection({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<String> rooms,
    required Set<String> mutedSet,
    required Function(String, bool) onToggle,
  }) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        dense: true,
        children: rooms.map((room) {
          final isVisible = !mutedSet.contains(room);
          return CheckboxListTile(
            title: Text(room),
            value: isVisible,
            activeColor: iconColor,
            dense: true,
            contentPadding: const EdgeInsets.only(left: 40, right: 20),
            onChanged: (val) => onToggle(room, !(val ?? false)),
          );
        }).toList(),
      ),
    );
  }
}
